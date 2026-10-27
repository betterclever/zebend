"""ZIP 221 chain history tree of the Zebend full node: every header's hashLightClientRoot
(Heartwood, Canopy) / hashBlockCommitments (NU5 on) checked in Bend (bin/history, from
consensus/gaps/history: node data V1/V2/V3, BLAKE2b "ZcashHistory"||branch id, MMR append and
peak bagging as zcash_history 0.6.0, reset at every activation, ZIP 244 hashAuthDataRoot).

Inputs Bend does not find in the block: the Sapling, Orchard and Ironwood roots after each block
(side.bin), from the node's own Bend trees (trees.py). A wrong root cannot produce a matching
commitment, so every MATCH also authenticates those roots (and the per-pool tx counts Bend
derives from the blocks).

State: meta "history" = {"state": hex of bin/history's state file (MMR peaks, ~3 KB),
"height": last block appended, "origin": text}. No state (None): the check is SKIPPED (never
PASS) until the next network upgrade activation, where the tree restarts empty. The state before
the first block of each window goes into that block's undo data (store.py), so a rollback to a
window boundary restores it; a rollback into the middle of a window drops it (SKIPPED until the
next activation, or until history_init.py rebuilds it).

Block h's own roots are checked by block h+1's header: the last block of a window is checked by
the next window (the window's last root is carried in the state).
"""
import re, struct, subprocess
from pathlib import Path

import headers

HERE = Path(__file__).resolve().parent
BIN = HERE / "bin"
HDR = 1487
HEARTWOOD = 903000
# mainnet activation heights from Heartwood on (Zebra network_upgrade.rs; NU7: ZIP 259)
ACTIVATIONS = [903000, 1046400, 1687104, 2726400, 3146400, 3364600, 3428143, 3543405]
SIDE_POOLS = ["sapling", "orchard", "ironwood"]


class HistoryFail(Exception):
    pass


def window_start_below(st, h):
    """The highest g <= h such that block g+1 has the ZIP 221 state before it in its undo data
    (it started a window), so store.rollback_to(g) restores the history state exactly. h itself
    if there is none within the undo depth (the history is then dropped, as before)."""
    import pickle
    k = h + 1
    while k > 0:
        r = st.rdb.execute("SELECT data FROM undo WHERE height=?", (k,)).fetchone()
        if r is None:
            return h
        if "history" in pickle.loads(r[0]):
            return k - 1
        k -= 1
    return h


class History:
    def __init__(self, st, work, log):
        self.st, self.work, self.log = st, Path(work), log
        self.work.mkdir(parents=True, exist_ok=True)
        self.cur = st.get("history")

    def reload(self):
        self.cur = self.st.get("history")

    def run(self, blocks, raw_by_height, after, tag):
        """Check every block of the window. after: {pool: {height: root after the block}} from
        trees.py (pools not tracked are absent). Returns a summary dict; raises HistoryFail on a
        MISMATCH. Sets b["history_before"] on the window's first block (undo data)."""
        first, last = blocks[0]["height"], blocks[-1]["height"]
        cur = self.cur
        if last < HEARTWOOD:
            return {"checked": 0, "skipped": 0, "n/a": len(blocks), "why": ""}
        if cur is None or cur["height"] != first - 1:
            # restart at an activation inside the window: the tree is empty there
            act = [a for a in ACTIVATIONS if first <= a <= last]
            if not act:
                return {"checked": 0, "skipped": len(blocks), "why": "no history state (starts at the next activation)"
                        if cur is None else f"history state at {cur['height']}, window starts at {first}"}
            blocks_run = [b for b in blocks if b["height"] >= act[0]]
            state_in, skipped_pre = "-", len(blocks) - len(blocks_run)
            origin = f"started empty at activation {act[0]}"
        else:
            blocks_run, skipped_pre = blocks, 0
            state_in = self.work / f"hist_{tag}.in"
            state_in.write_bytes(bytes.fromhex(cur["state"]))
            origin = cur["origin"]
        missing = []
        side = []
        for b in blocks_run:
            h = b["height"]
            rec = [struct.pack("<I", h)]
            for pool in SIDE_POOLS:
                adds = bool(b["leaves"].get(pool))
                r = after.get(pool, {}).get(h)
                if r is None:
                    if adds:
                        missing.append((h, pool))
                    rec.append(bytes(32))  # "unchanged" (only valid if the block adds no notes to the pool)
                else:
                    rec.append(bytes.fromhex(r))
            side.append(b"".join(rec))
        if missing:
            self.cur = None  # cannot continue the tree without these roots
            return {"checked": 0, "skipped": len(blocks),
                    "why": f"tree roots not tracked for {sorted({p for _, p in missing})} (first at {missing[0][0]}); "
                           f"history dropped until the next activation"}
        wp, sp, so = (self.work / f"hist_{tag}.{x}" for x in ("win", "side", "out"))
        last_hdr = headers.last_height()
        with open(wp, "wb") as f:
            for b in blocks_run:
                h = b["height"]
                raw = raw_by_height[h]
                exp = headers.header(h) if 1 <= h <= last_hdr else raw[:HDR]
                f.write(struct.pack("<I", h) + exp + struct.pack("<I", len(raw)) + raw)
        sp.write_bytes(b"".join(side))
        out = ""
        for _ in range(3):  # empty output (a known rare Bend runtime issue) is rerun, never a pass
            r = subprocess.run([str(BIN / "history"), str(state_in), str(wp), str(sp), str(so), "main"],
                               capture_output=True, text=True)
            out = r.stdout
            if out.strip():
                break
        lines = {int(h): rest for h, rest in re.findall(r"^hist (\d+) (.*)$", out, re.M)}
        bad = [(h, v) for h, v in lines.items() if v.startswith("MISMATCH")]
        if bad:
            raise HistoryFail(f"block {bad[0][0]}: ZIP 221 header commitment {bad[0][1][:200]}")
        miss = [b["height"] for b in blocks_run if b["height"] not in lines]
        if miss:
            raise HistoryFail(f"bin/history gave no verdict for {miss[:3]} ({r.stderr.strip()[-200:]!r})")
        n_match = sum(1 for v in lines.values() if v.startswith("MATCH"))
        n_skip = sum(1 for v in lines.values() if v.startswith("SKIP")) + skipped_pre
        n_na = sum(1 for v in lines.values() if v.startswith("n/a"))
        blocks[0]["history_before"] = cur  # undo data (None: there was none)
        self.cur = {"state": so.read_bytes().hex(), "height": last, "origin": origin}
        for p in (wp, sp, so):
            p.unlink(missing_ok=True)
        if state_in != "-":
            Path(state_in).unlink(missing_ok=True)
        return {"checked": n_match, "skipped": n_skip, "n/a": n_na,
                "why": "activation block (commits to the previous epoch's tree, not held)" if n_skip else ""}
