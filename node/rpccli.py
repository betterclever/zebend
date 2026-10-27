#!/usr/bin/env python3
"""Tiny JSON-RPC client: rpccli.py [--port P] METHOD [JSON params...]  (zcash-cli style)."""
import json, sys, urllib.request

args = sys.argv[1:]
port = 8232
if args and args[0] == "--port":
    port, args = int(args[1]), args[2:]
params = []
for a in args[1:]:
    try:
        params.append(json.loads(a))
    except ValueError:
        params.append(a)
req = urllib.request.Request(f"http://127.0.0.1:{port}/", data=json.dumps(
    {"jsonrpc": "1.0", "id": 1, "method": args[0], "params": params}).encode(),
    headers={"Content-Type": "application/json"})
r = json.load(urllib.request.urlopen(req, timeout=120))
if r.get("error"):
    print("error:", json.dumps(r["error"]))
    sys.exit(1)
print(json.dumps(r["result"], indent=1) if not isinstance(r["result"], str) else r["result"])
