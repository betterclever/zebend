#!/usr/bin/env python3
"""lightwalletd's mempool gRPC methods served from the Zebend mempool.

Starts the real lightwalletd (../../lwd-build, zcash/lightwalletd 4abfe9cd) with the mempool's RPC
port (18234) as its zcashd (--nocache: no block ingestion; --no-backend-check: it accepts only
zebrad/zakura/zcashd subversions), then compares over gRPC (grpcurl):
  GetMempoolTx (all pool types)  vs  getrawmempool       (same txids)
  GetMempoolTx (default: shielded pools only)
  GetMempoolStream (until the deadline)  vs  getrawmempool
usage: python3 tests/test_lightwalletd.py
"""
import base64, json, subprocess, sys, time, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
MP = HERE.parent
LWD = MP.parent.parent.parent / "lwd-build"
SVC = "cash.z.wallet.sdk.rpc.CompactTxStreamer"


def rpc(method, *params):
    req = urllib.request.Request("http://127.0.0.1:18234/", data=json.dumps(
        {"jsonrpc": "1.0", "id": 1, "method": method, "params": list(params)}).encode())
    return json.load(urllib.request.urlopen(req, timeout=60))["result"]


def grpc(method, req, max_time=None):
    cmd = [str(LWD / "bin/grpcurl"), "-plaintext"] + (["-max-time", str(max_time)] if max_time else []) + \
          ["-d", json.dumps(req), "127.0.0.1:19067", f"{SVC}/{method}"]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=120).stdout
    objs, dec, i = [], json.JSONDecoder(), 0
    while True:
        s = out[i:].lstrip()
        if not s:
            break
        o, j = dec.raw_decode(s)
        objs.append(o)
        i = len(out) - len(s) + j
    return objs


def main():
    d = MP / "work" / "lwd"
    d.mkdir(parents=True, exist_ok=True)
    p = subprocess.Popen([str(LWD / "lightwalletd/lightwalletd"), "--no-tls-very-insecure", "--grpc-bind-addr",
                          "127.0.0.1:19067", "--http-bind-addr", "127.0.0.1:19068", "--rpchost", "127.0.0.1",
                          "--rpcport", "18234", "--rpcuser", "x", "--rpcpassword", "x", "--data-dir", str(d),
                          "--log-file", str(d / "lwd.log"), "--no-backend-check", "--nocache"],
                         stdout=open(d / "lwd.out", "w"), stderr=subprocess.STDOUT)
    res = {}
    try:
        time.sleep(5)
        info = grpc("GetLightdInfo", {})[0]
        print("GetLightdInfo:", info.get("blockHeight"), info.get("consensusBranchId"), info.get("zcashdSubversion"))
        mem = set(rpc("getrawmempool"))
        allp = grpc("GetMempoolTx", {"poolTypes": ["TRANSPARENT", "SAPLING", "ORCHARD", "IRONWOOD"]})
        ids = {base64.b64decode(o["txid"])[::-1].hex() for o in allp}
        mem2 = set(rpc("getrawmempool"))
        both = mem & mem2  # txs present before and after the call (the mempool moves meanwhile)
        res["GetMempoolTx_all"] = {"compact_txs": len(ids), "getrawmempool": len(mem2),
                                   "missing": sorted(both - ids), "extra": sorted(ids - mem - mem2)}
        print(f"GetMempoolTx (all pools): {len(ids)} txs; getrawmempool {len(mem2)}; "
              f"missing {len(both - ids)}, not in mempool {len(ids - mem - mem2)}")
        sh = grpc("GetMempoolTx", {})
        res["GetMempoolTx_shielded"] = len(sh)
        print(f"GetMempoolTx (default, shielded pools): {len(sh)} txs")
        grpc("GetMempoolStream", {}, max_time=3)  # the first call after start only syncs the tip hash
        st = grpc("GetMempoolStream", {}, max_time=15)
        mem3 = set(rpc("getrawmempool"))
        res["GetMempoolStream"] = {"raw_txs": len(st), "getrawmempool": len(mem3),
                                   "heights": sorted({o.get("height", "0") for o in st})}
        print(f"GetMempoolStream: {len(st)} raw txs streamed (height field {res['GetMempoolStream']['heights']}); "
              f"getrawmempool {len(mem3)}")
        ok = not res["GetMempoolTx_all"]["missing"] and not res["GetMempoolTx_all"]["extra"] and len(st) > 0
        res["verdict"] = "PASS" if ok else "FAIL"
        print("LIGHTWALLETD MEMPOOL TEST", res["verdict"])
    finally:
        p.terminate()
        p.wait(10)
        (HERE / "results").mkdir(exist_ok=True)
        (HERE / "results" / "lightwalletd.json").write_text(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()
