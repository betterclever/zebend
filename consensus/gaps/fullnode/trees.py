"""Note commitment trees and anchors of the Zebend full node (Sprout, Sapling, Orchard).

Every hash is Bend; this module moves bytes between the window, the Bend tree programs and
the store, and compares what Bend prints:
  bin/sapling_frontier  Sapling tree (MerkleCRH^Sapling, Pedersen; sapling/tree/stree.bend)
  bin/orchard_frontier  Orchard and Ironwood trees (MerkleCRH^Orchard, Sinsemilla; fast/state32,
                        as follow uses for Ironwood). The Ironwood tree feeds the ZIP 221 node
                        data (history.py); Ironwood anchors are still checked by sync.py against
                        follow's Bend roots.
  bin/sprout_js         Sprout tree (SHA256Compress) + the JoinSplit anchor rule with
                        zcashd's interstitial trees (Bend decides validity)
  bin/sprout            Sprout tree from a leaf prefix (the frontier of an older anchor)
(sources: consensus/gaps/trees/*.bend; fullnode/trees/sprout.bend)

State: meta "trees" = {pool: {"frontier": [levels], "size": n, "root": hex, "origin": text}}.
A pool absent from meta is not tracked in this instance: its anchors are reported SKIPPED
(never PASS). Per block: b["roots"][pool] (root after a block that appends leaves: the store's
anchor index, with undo) and b["trees_before"][pool] (the pool's state before that block: the
store's undo data restores it on a rollback).

Anchor rule (protocol spec 4.6; Zebra zebra-state service/check/anchors.rs; zcashd
CCoinsViewCache::HaveShieldedRequirements): a Sapling spend's / Orchard bundle's anchor must be
the tree root after some block strictly before the transaction's block (the empty tree's root
included); a Sprout JoinSplit's anchor may also be an interstitial root of the same tx.

Header check: for Sapling-era blocks before Heartwood (419,200 <= h < 903,000) the header's
hashFinalSaplingRoot must equal the Bend root after the block. From Heartwood on the per-block
Sapling/Orchard roots are committed through the ZIP 221 history tree (see history.py).
"""
import json, re, struct, subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
BIN = HERE / "bin"
TREE_POOLS = ["sprout", "sapling", "orchard", "ironwood"]  # = store.POOLS order (anchor table pool ids)
TOOL = {"sapling": "sapling_frontier", "orchard": "orchard_frontier", "ironwood": "orchard_frontier"}
DEPTH = {"sprout": 29, "sapling": 32, "orchard": 32, "ironwood": 32}
SAPLING, HEARTWOOD = 419200, 903000
EMPTY = {}  # pool -> empty tree root (printed by the Bend tools)


class AnchorFail(Exception):
    pass


def _run(args):
    for _ in range(3):  # empty output (a known rare Bend runtime issue) is rerun
        r = subprocess.run([str(a) for a in args], capture_output=True, text=True)
        if r.stdout.strip():
            return r.stdout
    raise AnchorFail(f"{Path(str(args[0])).name} printed nothing (exit {r.returncode}: {r.stderr.strip()[-200:]!r})")


def _fr_text(levels, depth):
    return "\n".join((levels + ["-"] * depth)[:depth]) + "\n"


class Trees:
    def __init__(self, st, work, log):
        self.st, self.work, self.log = st, Path(work), log
        self.work.mkdir(parents=True, exist_ok=True)
        self.cur = st.get("trees") or {}
        self.recent = {p: {} for p in TREE_POOLS}       # root -> height, roots computed this session
        self.recent_front = {}                          # sprout root -> frontier levels (this session)
        for pool in self.cur:                           # the empty roots (also valid anchors)
            self.empty_root(pool)

    def empty_root(self, pool):
        if pool not in EMPTY:
            lp, cp, fo = (self.work / f"empty_{pool}.{x}" for x in ("leaves", "counts", "frontier"))
            lp.write_bytes(b"")
            cp.write_bytes(struct.pack("<I", 0))
            tool = BIN / (TOOL.get(pool) or "sprout")
            EMPTY[pool] = re.search(r"^empty_root ([0-9a-f]{64})$", _run([tool, "-", lp, cp, fo]), re.M).group(1)
        return EMPTY[pool]

    def reload(self):
        """After a rollback (store.rollback_to restored meta "trees")."""
        self.cur = self.st.get("trees") or {}
        self.recent = {p: {} for p in TREE_POOLS}
        self.recent_front = {}

    # ------------------------------------------------------------ advance the trees
    def advance(self, blocks, raw_by_height, tag):
        """Append every block's leaves; per block roots (b["roots"]) and the state before each
        changing block (b["trees_before"]). Returns {pool: {height: root after the block}} for
        every block of the window (blocks that append nothing keep the previous root), and
        stores the window's Sprout JoinSplit verdicts in self.sprout_verdicts."""
        after = {}
        self.sprout_verdicts = None
        for pool in TREE_POOLS:
            if pool not in self.cur:
                continue
            if pool == "sprout":
                after[pool] = self._advance_sprout(blocks, tag)
            else:
                after[pool] = self._advance(pool, blocks, tag)
        for b in blocks:  # pre-Heartwood headers commit to the Sapling root directly
            h = b["height"]
            if "sapling" in after and SAPLING <= h < HEARTWOOD:
                hdr = raw_by_height[h][68:100].hex()
                if hdr != after["sapling"][h]:
                    raise AnchorFail(f"block {h}: header hashFinalSaplingRoot {hdr[:16]} != Bend Sapling root "
                                     f"{after['sapling'][h][:16]}")
        return after

    def _state_in(self, pool):
        c = self.cur[pool]
        p = self.work / f"{pool}_in.frontier"
        p.write_text(_fr_text(c["frontier"], DEPTH[pool]))
        return p

    def _advance(self, pool, blocks, tag):
        c = self.cur[pool]
        leaves = [(b, b["leaves"][pool]) for b in blocks]
        res = {}
        if not any(cms for _, cms in leaves):
            for b in blocks:
                res[b["height"]] = c["root"]
            return res
        lp, cp, fo = (self.work / f"{pool}_{tag}.{x}" for x in ("leaves", "counts", "frontier"))
        lp.write_bytes(b"".join(bytes.fromhex(x) for _, cms in leaves for x in cms))
        cp.write_bytes(b"".join(struct.pack("<I", len(cms)) for _, cms in leaves))
        out = _run([BIN / TOOL[pool], self._state_in(pool), lp, cp, fo])
        roots = {int(i): r for i, _s, r in re.findall(r"^root (\d+) (\d+) ([0-9a-f]{64})$", out, re.M)}
        fronts = {int(i): f.split(",") for i, f in re.findall(r"^front (\d+) (\S+)$", out, re.M)}
        EMPTY[pool] = re.search(r"^empty_root ([0-9a-f]{64})$", out, re.M).group(1)
        want = [i for i, (_, cms) in enumerate(leaves) if cms]
        if sorted(roots) != want or sorted(fronts) != want:
            raise AnchorFail(f"{TOOL[pool]}: roots for blocks {sorted(roots)[:5]}..., expected {want[:5]}...")
        state = dict(c)
        for i, (b, cms) in enumerate(leaves):
            if cms:
                b.setdefault("trees_before", {})[pool] = state
                state = dict(state, frontier=fronts[i], size=state["size"] + len(cms), root=roots[i])
                b.setdefault("roots", {})[pool] = roots[i]
                self.recent[pool].setdefault(roots[i], b["height"])
            res[b["height"]] = state["root"]
        if fo.read_text().split("\n")[:DEPTH[pool]] != state["frontier"]:
            raise AnchorFail(f"{TOOL[pool]}: final frontier differs from the last block's")
        self.cur[pool] = state
        for p in (lp, cp, fo):
            p.unlink(missing_ok=True)
        return res

    # ------------------------------------------------------------ Sprout
    def _sprout_known(self, root, before):
        """Height of a Sprout root of a block < before (session or the store's anchor index)."""
        h = self.recent["sprout"].get(root)
        if h is not None and h < before:
            return h
        r = self.st.rdb.execute("SELECT height FROM anchor WHERE pool=0 AND root=?", (bytes.fromhex(root),)).fetchone()
        return r[0] if r and r[0] < before else None

    def _sprout_frontier_at(self, root, height):
        """Frontier of the Sprout tree whose root is `root` (the tree after block `height`):
        from this session, or rebuilt in Bend (bin/sprout) from the leaf log's prefix; its root
        is compared with `root` (and sprout_js re-derives every root it uses from it)."""
        if root in self.recent_front:
            return self.recent_front[root]
        a, b = self.st.leaf_paths("sprout")
        idx = Path(b).read_bytes()
        n = 0
        for i in range(0, len(idx), 8):
            hh, c = struct.unpack_from("<II", idx, i)
            if hh > height:
                break
            n += c
        lp, cp, fo = (self.work / f"sprout_prefix.{x}" for x in ("leaves", "counts", "frontier"))
        with open(a, "rb") as f:
            lp.write_bytes(f.read(n * 32))
        cp.write_bytes(struct.pack("<I", n))
        out = _run([BIN / "sprout", "-", lp, cp, fo])
        m = re.search(r"^root 0 \d+ ([0-9a-f]{64})$", out, re.M)
        if not m or m.group(1) != root:
            return None
        return fo.read_text().split("\n")[:29]

    def _advance_sprout(self, blocks, tag):
        c = self.cur["sprout"]
        start = blocks[0]["height"]
        js = []  # (block index, tx index, anchor, cm1, cm2)
        for bi, b in enumerate(blocks):
            cms = b["leaves"]["sprout"]
            k = 0
            for t in b["txs"]:
                for j in t["js"]:
                    js.append((bi, t["i"], j["anchor"], cms[k], cms[k + 1]))
                    k += 2
            if k != len(cms):
                raise AnchorFail(f"block {b['height']}: Sprout commitments do not match its JoinSplits")
        res = {}
        if not js:
            for b in blocks:
                res[b["height"]] = c["root"]
            self.sprout_verdicts = []
            return res
        # ext: the anchors that are roots of blocks before the window (store index or session);
        # frontiers for those that start a tx with >= 2 JoinSplits (interstitial roots).
        ntx = {}
        for bi, ti, *_ in js:
            ntx[(bi, ti)] = ntx.get((bi, ti), 0) + 1
        ext = []
        for a in sorted({j[2] for j in js}):
            h = self._sprout_known(a, start)
            if h is None:
                continue
            fr = None
            if any(ntx[(bi, ti)] > 1 and aa == a for bi, ti, aa, _, _ in js):
                fr = self._sprout_frontier_at(a, h)
            ext.append((a, fr))
        jb = [struct.pack("<I", len(js))]
        for bi, ti, a, c1, c2 in js:
            jb.append(struct.pack("<II", bi, ti) + bytes.fromhex(a) + bytes.fromhex(c1) + bytes.fromhex(c2))
        xb = [struct.pack("<I", len(ext))]
        for a, fr in ext:
            xb.append(bytes.fromhex(a))
            if fr is None:
                xb.append(struct.pack("<I", 0))
            else:
                xb.append(struct.pack("<I", 1))
                xb += [struct.pack("<I", 0) + bytes(32) if lv in ("-", "") else struct.pack("<I", 1) + bytes.fromhex(lv)
                       for lv in fr]
        jp, xp, fo = (self.work / f"sprout_{tag}.{x}" for x in ("js", "ext", "frontier"))
        jp.write_bytes(b"".join(jb))
        xp.write_bytes(b"".join(xb))
        out = _run([BIN / "sprout_js", self._state_in("sprout"), jp, xp, fo])
        verd = {int(k): v for k, v in re.findall(r"^js (\d+) ([WEIXZ])$", out, re.M)}
        if len(verd) != len(js):
            raise AnchorFail(f"sprout_js: {len(verd)} verdicts for {len(js)} JoinSplits")
        roots = {int(i): r for i, _s, r in re.findall(r"^root (\d+) (\d+) ([0-9a-f]{64})$", out, re.M)}
        fronts = {int(i): f.split(",") for i, f in re.findall(r"^front (\d+) (\S+)$", out, re.M)}
        EMPTY["sprout"] = re.search(r"^empty_root ([0-9a-f]{64})$", out, re.M).group(1)
        state = dict(c)
        for bi, b in enumerate(blocks):
            if bi in roots:
                b.setdefault("trees_before", {})["sprout"] = state
                state = dict(state, frontier=fronts[bi], size=state["size"] + len(b["leaves"]["sprout"]), root=roots[bi])
                b.setdefault("roots", {})["sprout"] = roots[bi]
                self.recent["sprout"].setdefault(roots[bi], b["height"])
                self.recent_front[roots[bi]] = fronts[bi]
            res[b["height"]] = state["root"]
        if len(self.recent_front) > 2000:
            for k in list(self.recent_front)[:1000]:
                del self.recent_front[k]
        self.cur["sprout"] = state
        self.sprout_verdicts = [(blocks[bi]["height"], ti, a, verd[k]) for k, (bi, ti, a, _, _) in enumerate(js)]
        for p in (jp, xp, fo):
            p.unlink(missing_ok=True)
        return res

    # ------------------------------------------------------------ anchors (full validation)
    def _known(self, pool, root, h, first):
        """root is the root after a block < h: this window (first: root -> first height it was the
        root after, incl. the block before the window), this session, or the store's index."""
        if root == EMPTY.get(pool):
            return True
        if first.get(root, h) < h:
            return True
        r = self.recent[pool].get(root)
        if r is not None and r < h:
            return True
        x = self.st.rdb.execute("SELECT height FROM anchor WHERE pool=? AND root=?",
                                (TREE_POOLS.index(pool), bytes.fromhex(root))).fetchone()
        return bool(x) and x[0] < h

    def check_anchors(self, full, after, prev_root):
        """Raise AnchorFail on an invalid anchor; returns {pool: (checked, skipped, why)}."""
        out = {}
        for pool in ("sapling", "orchard"):
            n = sk = old = 0
            first = {}
            if pool in self.cur:
                first[prev_root[pool]] = full[0]["height"] - 1
                for hh in sorted(after.get(pool, {})):
                    first.setdefault(after[pool][hh], hh)
            for b in full:
                for t in b["txs"]:
                    for a in set(t["anchors"][pool]):
                        if pool not in self.cur:
                            sk += 1
                            continue
                        if not self._known(pool, a, b["height"], first):
                            hf = self.cur[pool].get("history_from")
                            if hf is not None:
                                # an instance whose root history starts at hf cannot tell an older
                                # root from an invalid one: SKIPPED (never PASS), with the reason
                                old += 1
                                continue
                            raise AnchorFail(f"block {b['height']} tx {t['txid']}: {pool} anchor {a[:16]} is not "
                                             f"a root of an earlier block")
                        n += 1
            why = "tree not tracked in this instance" if sk else ""
            if old:
                sk += old
                why = f"anchor not in the root history, which starts at {self.cur[pool]['history_from']}"
            out[pool] = (n, sk, why)
        n = sk = 0
        fullh = {b["height"] for b in full}
        if "sprout" not in self.cur:
            sk = sum(len(t["js"]) for b in full for t in b["txs"])
        else:
            for h, ti, a, v in self.sprout_verdicts or []:
                if h not in fullh:
                    continue
                if v not in "WEI":
                    raise AnchorFail(f"block {h} tx {ti}: Sprout anchor {a[:16]} is neither a root of an earlier "
                                     f"block nor an interstitial root of the transaction ({v})")
                n += 1
        out["sprout"] = (n, sk, "no Sprout tree before the assumed start" if sk else "")
        return out
