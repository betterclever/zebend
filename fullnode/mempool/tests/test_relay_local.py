#!/usr/bin/env python3
"""Local relay and protocol test between two extra mempool instances (no internet peers).

  B: --no-seeds, listens on 18250 (RPC 18251)       C: --no-seeds --connect 127.0.0.1:18250 (RPC 18253)
  1. real transactions taken from the running mempool (received from mainnet peers) are sent to
     B with sendrawtransaction (RPC): B validates and admits them, announces them by inv to C;
     C asks B with getdata, B serves `tx`, C validates and admits them (source "p2p 127.0.0.1")
  2. sendrawtransaction of a tx already in B's mempool returns its txid (zcashd behaviour)
  3. a raw-socket client checks B's protocol answers: version/verack, ping -> pong,
     getaddr -> addr, mempool -> inv (MSG_TX / MSG_WTX), getdata -> tx, getdata unknown -> notfound
  4. rate limit: the client floods B with pings; B must stop answering and disconnect it
Both instances read state-tip read-only. Nothing is sent to the internet.
"""
import json, os, socket, struct, subprocess, sys, time, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
MP = HERE.parent
sys.path.insert(0, str(MP))
import p2p
sys.path.insert(0, str(MP.parent))
import net

W = MP / "work" / "relay"


def rpc(port, method, *params):
    req = urllib.request.Request(f"http://127.0.0.1:{port}/", data=json.dumps(
        {"jsonrpc": "1.0", "id": 1, "method": method, "params": list(params)}).encode(),
        headers={"Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req, timeout=300))
    if r.get("error"):
        raise RuntimeError(r["error"])
    return r["result"]


def wait(cond, secs, what):
    t = time.time()
    while time.time() - t < secs:
        try:
            v = cond()
            if v:
                return v
        except Exception:
            pass
        time.sleep(0.5)
    raise TimeoutError(what)


def start(name, args):
    d = W / name
    d.mkdir(parents=True, exist_ok=True)
    log = open(d / "mempool.log", "w")
    return subprocess.Popen([sys.executable, "-u", str(MP / "mempool.py"), "--state", str(MP.parent / "state-tip"),
                             "--data", str(d), "--journal", str(d / "journal.jsonl"), "--no-seeds", *args],
                            stdout=log, stderr=subprocess.STDOUT, env=dict(os.environ, BEND_NO_TELEMETRY="1"))


def main():
    out, checks = {}, []

    def check(name, ok, detail=""):
        checks.append((name, bool(ok), detail))
        print(f"  {'PASS' if ok else 'FAIL'}  {name} {detail}")

    W.mkdir(parents=True, exist_ok=True)
    for f in W.glob("*/journal.jsonl"):
        f.unlink()
    B = start("B", ["--port", "18250", "--rpc-port", "18251"])
    C = start("C", ["--port", "18252", "--rpc-port", "18253", "--no-listen", "--connect", "127.0.0.1:18250"])
    try:
        wait(lambda: rpc(18251, "getmempoolinfo") and rpc(18253, "getmempoolinfo"), 60, "rpc up")
        wait(lambda: any(p["inbound"] for p in rpc(18251, "getpeerinfo")), 60, "C connected to B")
        print("C connected to B")
        live = rpc(18234, "getrawmempool")[:8]
        raws = {t: rpc(18234, "getrawtransaction", t, 0) for t in live}
        print(f"{len(raws)} live txs from the running mempool (received from mainnet peers)")
        got = {}
        for t, h in raws.items():
            try:
                got[t] = rpc(18251, "sendrawtransaction", h)
            except RuntimeError as e:
                got[t] = f"error {e}"
        okB = [t for t in raws if got[t] == t]
        check("B admits the txs via sendrawtransaction", len(okB) == len(raws), f"{len(okB)}/{len(raws)}")
        for t in raws:
            if got[t] != t:
                print(f"     {t[:16]}: {got[t]}")
        wait(lambda: set(okB) <= set(rpc(18253, "getrawmempool")), 120, "C has B's txs")
        memC = set(rpc(18253, "getrawmempool"))
        check("C receives them over P2P (inv -> getdata -> tx) and admits them", set(okB) <= memC,
              f"{len(set(okB) & memC)}/{len(okB)}")
        jc = [json.loads(l) for l in open(W / "C" / "journal.jsonl")]
        src = {j["txid"]: j["source"] for j in jc if j.get("status") == "admitted"}
        check("C's source for them is the P2P peer B", all(src.get(t, "").startswith("p2p 127.0.0.1") for t in okB),
              str(sorted(set(src.values()))))
        sB = rpc(18251, "getmempoolstats")
        check("B served them (getdata -> tx)", sB["p2p"].get("tx served", 0) >= len(okB), f"tx served {sB['p2p'].get('tx served')}")
        if okB:
            again = rpc(18251, "sendrawtransaction", raws[okB[0]])
            check("sendrawtransaction of a tx already in the mempool returns its txid", again == okB[0])
        # 3. raw protocol client against B
        s = socket.create_connection(("127.0.0.1", 18250), timeout=5)
        c = p2p.Conn(None, s, "127.0.0.1", 18250, False)
        c.handshake(0, 777, 0)
        check("handshake version/verack", c.ready, c.ua)
        replies = {}

        def ask(cmd, payload, want, secs=5):
            c.send(cmd, payload)
            t = time.time()
            while time.time() - t < secs:
                try:
                    k, p = c.recv()
                except (socket.timeout, TimeoutError):
                    continue
                replies.setdefault(k, []).append(p)
                if k == want:
                    return p
            return None

        nonce = struct.pack("<Q", 4242)
        check("ping -> pong (same nonce)", ask("ping", nonce, "pong") == nonce)
        a = ask("getaddr", b"", "addr")
        check("getaddr -> addr", a is not None, f"{net.read_cs(a, 0)[0] if a else 0} entries")
        inv = ask("mempool", b"", "inv")
        ents = p2p.parse_inv(inv) if inv else []
        check("mempool -> inv of B's mempool", len(ents) >= len(okB),
              f"{len(ents)} entries, types {sorted({t for t, _ in ents})}")
        if ents:
            txp = ask("getdata", p2p.build_inv(ents[:1]), "tx")
            check("getdata (as announced) -> tx", txp is not None and txp.hex() in raws.values())
            wt = ents[0]
            if wt[0] == p2p.MSG_WTX:
                bad = (p2p.MSG_WTX, wt[1][:32] + bytes(32))
                nf = ask("getdata", p2p.build_inv([bad]), "notfound")
                check("getdata with a wrong auth digest -> notfound (ZIP 239)", nf is not None)
        nf = ask("getdata", p2p.build_inv([(p2p.MSG_TX, bytes(32))]), "notfound")
        check("getdata unknown tx -> notfound", nf is not None)
        # 4. rate limit: 3,000 pings at once
        c.s.settimeout(5)
        sent = 0
        try:
            for i in range(3000):
                c.send("ping", struct.pack("<Q", i))
                sent += 1
        except OSError:
            pass
        pongs, closed = 0, False
        t = time.time()
        while time.time() - t < 10:
            try:
                k, p = c.recv()
                pongs += k == "pong"
            except (socket.timeout, TimeoutError):
                break
            except (ConnectionError, OSError):
                closed = True
                break
        check("rate limit: flood of pings is cut off (not every ping answered, connection dropped)",
              pongs < sent and closed, f"sent {sent}, pongs {pongs}, disconnected {closed}")
        c.close()
        out["checks"] = [{"check": n, "ok": ok, "detail": d} for n, ok, d in checks]
    finally:
        for p in (B, C):
            p.terminate()
            p.wait(10)
    n_ok = sum(1 for _, ok, _ in checks if ok)
    print(f"\nRESULT: {n_ok}/{len(checks)} PASS")
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / "relay_local.json").write_text(json.dumps(out, indent=1))
    return 0 if n_ok == len(checks) else 1


if __name__ == "__main__":
    sys.exit(main())
