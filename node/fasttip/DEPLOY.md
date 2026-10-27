# Deploying node/fasttip (controlled restart under the supervisor)

What changes: the `sync` and `live` services become ONE service, `fasttip/tipsync.py` (sync.py
plus push pickup, in one process). `rpc`, `mempool` and `follow` are not touched and keep running
(the new supervisor adopts them). `node/state` is not modified by the deploy itself: tipsync
starts from the committed tip, exactly like a sync.py restart.

Files:
- new, already in place: `node/fasttip/{tipsync,tipfeed,inproc,prof}.py` (nothing imports them
  until the service is switched);
- patches to apply: `node/fasttip/patches/{sync,rules,trees}.diff` (made with `diff -u` against the
  live files as of Oct 28 02:03; `patch --dry-run` applies cleanly).

Times below assume the repo root `Z=/Users/betterclever/projects/zecathon/zebend`.

## 0. Pre-flight (no effect on the running node)

```sh
cd $Z
# patches apply to the files as they are now
T=$(mktemp -d); mkdir $T/node; cp node/{rules,sync,trees}.py $T/node/
(cd $T && for p in $Z/node/fasttip/patches/*.diff; do patch -p1 --dry-run < $p || echo "PATCH FAILS: $p"; done); rm -rf $T
# the new code compiles
/opt/homebrew/bin/python3 -m py_compile node/fasttip/*.py
# the supervisor's pid, and the sync / live pids it owns
pgrep -fl "node/ops/supervise.py run"
pgrep -fl "sync.py$" ; pgrep -fl "live.py --every"
```

## 1. Apply the patches and the new service config

Applying the patches while sync.py runs only raises the supervisor's CODE alert (it does not
restart anything); the running process keeps the old code until step 3.

```sh
cd $Z
cp node/rules.py node/rules.py.pre-fasttip; cp node/sync.py node/sync.py.pre-fasttip; cp node/trees.py node/trees.py.pre-fasttip
cp node/ops/zebend.json node/ops/zebend.json.pre-fasttip
for p in node/fasttip/patches/*.diff; do patch -p1 < $p; done
/opt/homebrew/bin/python3 -m py_compile node/rules.py node/sync.py node/trees.py
```

Edit `node/ops/zebend.json`: replace the `sync` and `live` entries with

```json
  {"name": "sync", "cwd": "node", "argv": ["{python}", "-u", "fasttip/tipsync.py", "--peers", "3", "--every", "60"],
   "log": "node/logs/sync.log", "stop_timeout": 120,
   "env": {"BEND_NO_TELEMETRY": "1"}, "watch": ["node/*.py", "node/bin/*", "node/hooks/*", "node/fasttip/*.py"],
   "progress": {"db": "node/state/chain.sqlite", "headers": "node/state/hdr/hashes.bin", "stall_min": 20}},
  {"name": "live", "enabled": false, "cwd": "node", "argv": ["{python}", "-u", "live.py", "--every", "60"], "log": "node/logs/live.log",
   "env": {"BEND_NO_TELEMETRY": "1"}},
```

(`live` is kept but disabled: tipsync runs the same tiphdr.py + download.py cycle itself as the
fallback, and two writers of `state/hdr` must never run at once.) Then:

```sh
/opt/homebrew/bin/python3 node/ops/supervise.py check node/ops/zebend.json
```

## 2. Stop the supervisor WITHOUT stopping its other services

The supervisor reads its config only at start, and on SIGTERM it stops every service it owns.
To keep rpc/mempool/follow running, end only the supervisor process with SIGKILL (its children
write to their log files, not to pipes, and keep running; the next supervisor adopts them by
command line + cwd):

```sh
kill -KILL $(pgrep -f "node/ops/supervise.py run")
```

## 3. Stop the old sync and live (the only services that change)

```sh
kill -TERM $(pgrep -f "Python -u sync.py$")    # sync.py finishes or drops the current window, commits, exits
kill -TERM $(pgrep -f "live.py --every 60")      # live.py has no state; a partial spool .part is cleaned by download.py
# wait until both are gone (sync: at most one window, normally < 1 s at the tip)
while pgrep -f "Python -u sync.py$" >/dev/null || pgrep -f "live.py --every" >/dev/null; do sleep 1; done
pgrep -fl "tiphdr.py|download.py" && echo "a tiphdr/download child of live.py is still running: wait for it"
```

## 4. Start the supervisor with the new config

```sh
cd $Z && nohup /opt/homebrew/bin/python3 -u node/ops/supervise.py run node/ops/zebend.json >> node/ops/supervisor.log 2>&1 &
sleep 20
/opt/homebrew/bin/python3 node/ops/supervise.py status node/ops/zebend.json   # rpc/mempool/follow "adopted", sync "owned"
tail -20 node/logs/sync.log
```

Expected in `node/logs/sync.log` within a minute:
`fasttip: push pickup on 3 peers, ...`, `sync: state tip ...`, `fasttip: push peer <ip> ...`; then
per block `fasttip: appended 1 header(s) ...` and
`fasttip: block <h> announced (inv) by <ip> -> verdict committed in 0.xxx s (fetch ..., header check ..., validate+commit ...)`.
Per-block timings also go to `node/logs/fasttip_latency.jsonl`
(`python3 node/fasttip/tools/summarize.py node/logs/fasttip_latency.jsonl`). Every 5 min a
`fasttip status:` line lists the push peers. If no push peer is connected, or push is quiet for
10 min, the log shows `fasttip fallback (...)`: the old live.py cycle, exactly as before.

## 5. Rollback

```sh
kill -KILL $(pgrep -f "node/ops/supervise.py run")
kill -TERM $(pgrep -f "fasttip/tipsync.py"); while pgrep -f "fasttip/tipsync.py" >/dev/null; do sleep 1; done
cd $Z && for f in rules sync trees; do cp node/$f.py.pre-fasttip node/$f.py; done
cp node/ops/zebend.json.pre-fasttip node/ops/zebend.json
nohup /opt/homebrew/bin/python3 -u node/ops/supervise.py run node/ops/zebend.json >> node/ops/supervisor.log 2>&1 &
```

The state written by tipsync is the state sync.py writes (same rules, verdicts and commits;
see README.md, "Equivalence"), so the old code continues from it without any conversion.

## Switches (environment of the sync service, no code change)

- `ZEBEND_PARALLEL_HOOKS=0`: hooks and tree pools one after another, as before.
- `ZEBEND_OVERLAP=0`: bin/rules + hooks after the trees/anchors, as before.
- `tipsync.py --no-inproc`: every hook as a subprocess, as before.
- `tipsync.py --hdr-poll 0`: no getheaders safety poll on the push connections.
- `tipsync.py --peers 0`: no push connections at all (fallback polling only: the old behaviour,
  minus the 5 s idle sleep).
The patched sync.py run on its own (`python3 sync.py`, no BLOCK_SOURCE) behaves as before except
for the parallel hooks / tree pools and the overlap, which are on by default (env above to turn off).

## Notes / caveats

- Peer slots: tipsync holds `--peers` (3) long-lived connections, preferring IPv6 addresses
  (a different source address from the IPv4 connections of follow / mempool) and avoiding
  follow's and tiphdr.py's fixed peers (net.KNOWN). During the tests most peers dropped or refused
  this IP within seconds (see README.md); the header poll and the fallback cover that.
- The fallback runs tiphdr.py while holding the header-index lock, so a push append waits for
  it; it runs only when kicked (fork, missed block), without push peers, or after 10 min of quiet.
