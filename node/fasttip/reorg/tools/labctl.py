#!/usr/bin/env python3
"""Lab tool (reorg tests): prepare a lab node state. Runs IN the lab's code (sys.path = <lab>/node).

  labctl.py --lab <lab>/node rollback H            store.rollback_to(window_start_below(H)), index cut to H
  labctl.py --lab <lab>/node setidx H --gold DIR   header index := the golden's (canonical) index up to H
  labctl.py --lab <lab>/node cutidx H              header index cut to H
  labctl.py --lab <lab>/node apply A B --blocks D  blocks A..B (D/<h>.bin) through sync.py, one block per
                                                   window (spool chunks, --window 1), index must cover B
  labctl.py --lab <lab>/node relabel A B [--harder K]
        TEST CONSTRUCTION: our committed blocks A..B (the tip) and their index entries are relabelled as
        a different branch: each header's nonce gets one byte flipped (so a different hash; these headers
        never had valid PoW and only stand for "a branch we accepted earlier"); blk rows, meta tip and
        the header index are rewritten consistently. --harder K: their nBits target is divided by 2^K
        (the branch claims more work: the "longer but less work" test).
  labctl.py --lab <lab>/node tip
"""
import argparse, hashlib, json, os, sqlite3, struct, subprocess, sys, time
from pathlib import Path

HDR, EXTRA_FIRST = 1487, 3528280


def sha256d(b):
    return hashlib.sha256(hashlib.sha256(b).digest()).digest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lab", required=True)
    ap.add_argument("cmd")
    ap.add_argument("args", nargs="*")
    ap.add_argument("--gold")
    ap.add_argument("--blocks")
    ap.add_argument("--harder", type=int, default=0)
    a = ap.parse_args()
    lab = Path(a.lab).resolve()
    assert lab.name == "node" and "zebend/node" not in str(lab), "lab only"
    os.environ.update(ZEBEND_STATE=str(lab / "state"), ZEBEND_SPOOL=str(lab / "spool"), BEND_NO_TELEMETRY="1")
    sys.path.insert(0, str(lab))
    hdr = lab / "state/hdr"

    def cut(H):
        with open(hdr / "hashes.bin", "r+b") as f:
            f.truncate((H + 1) * 32)
        with open(hdr / "extra.bin", "r+b") as f:
            f.truncate((H + 1 - EXTRA_FIRST) * HDR)

    if a.cmd == "tip":
        import store as S
        st = S.Store(lab / "state")
        n = (hdr / "hashes.bin").stat().st_size // 32
        print(f"state tip {st.tip()}; index to {n - 1}")
    elif a.cmd == "rollback":
        import store as S, history as HI
        H = int(a.args[0])
        st = S.Store(lab / "state")
        h0 = HI.window_start_below(st, H)
        t = time.time()
        st.rollback_to(h0)
        print(f"rolled back to {h0} (asked {H}) in {time.time() - t:.1f} s; tip {st.tip()}")
        st.close()
        cut(h0)
    elif a.cmd == "cutidx":
        cut(int(a.args[0]))
    elif a.cmd == "setidx":
        H, g = int(a.args[0]), Path(a.gold)
        n = (H + 1) * 32
        hb = (g / "hdr/hashes.bin").read_bytes()[:n]
        eb = (g / "hdr/extra.bin").read_bytes()[:(H + 1 - EXTRA_FIRST) * HDR]
        assert len(hb) == n and len(eb) == (H + 1 - EXTRA_FIRST) * HDR
        (hdr / "hashes.bin").write_bytes(hb)
        (hdr / "extra.bin").write_bytes(eb)
        print(f"index set to {H} from {g}")
    elif a.cmd == "apply":
        A, B = int(a.args[0]), int(a.args[1])
        for p in (lab / "spool").glob("*"):
            p.unlink()
        for h in range(A, B + 1):
            raw = (Path(a.blocks) / f"{h}.bin").read_bytes()
            (lab / "spool" / f"{h}.blk").write_bytes(struct.pack("<II", h, len(raw)) + raw)
        r = subprocess.run([sys.executable, "-u", str(lab / "sync.py"), "--to", str(B), "--window", "1"],
                           cwd=lab, capture_output=True, text=True)
        print("\n".join(l for l in (r.stdout + r.stderr).splitlines() if "committed tip" in l or "FAIL" in l or "REORG" in l))
        assert r.returncode == 0, r.stdout[-2000:] + r.stderr[-2000:]
    elif a.cmd == "relabel":
        A, B = int(a.args[0]), int(a.args[1])
        db = sqlite3.connect(lab / "state/chain.sqlite")
        tip = json.loads(db.execute("SELECT v FROM meta WHERE k='tip'").fetchone()[0])
        assert tip["height"] == B, tip
        ext = bytearray((hdr / "extra.bin").read_bytes())
        hs = bytearray((hdr / "hashes.bin").read_bytes())
        assert len(hs) // 32 == B + 1, "index must end at the tip"
        prev = None
        db.execute("BEGIN")
        for h in range(A, B + 1):
            o = (h - EXTRA_FIRST) * HDR
            x = bytearray(ext[o:o + HDR])
            if prev is not None:
                x[4:36] = prev
            x[108] ^= 0x5A  # nonce byte: a different header (no valid PoW: it stands for an earlier-accepted branch)
            if a.harder:
                bits = struct.unpack_from("<I", x, 104)[0]
                exp, mant = bits >> 24, bits & 0x7FFFFF
                exp -= a.harder // 8
                mant >>= a.harder % 8
                struct.pack_into("<I", x, 104, (exp << 24) | mant)
            ext[o:o + HDR] = x
            nm = sha256d(bytes(x))
            hs[h * 32:(h + 1) * 32] = nm
            db.execute("UPDATE blk SET hash=? WHERE height=?", (nm[::-1], h))
            if prev is not None:
                db.execute("UPDATE blk SET prev=? WHERE height=?", (prev[::-1], h))
            prev = nm
        db.execute("UPDATE meta SET v=? WHERE k='tip'", (json.dumps({"height": B, "hash": prev[::-1].hex()}),))
        db.execute("COMMIT")
        db.close()
        (hdr / "extra.bin").write_bytes(bytes(ext))
        (hdr / "hashes.bin").write_bytes(bytes(hs))
        print(f"relabelled {A}..{B}: tip hash now {prev[::-1].hex()}" + (f" (nBits harder by 2^{a.harder})" if a.harder else ""))
    else:
        raise SystemExit(f"unknown command {a.cmd}")


if __name__ == "__main__":
    main()
