"""Assumed-state mode (the fallback when a genesis sync is too slow): spent outputs from an oracle.

A node that starts just below the last checkpoint has no UTXO set for older outputs. For every
transparent input whose output the node has not seen, this module asks lightwalletd for the
creating transaction (node/follow/bin/follow-lwd, a labelled oracle) and then lets Bend decide what
it says: the transaction is run through bin/blockdelta (wire validator + txid), and is used only
if the Bend-computed txid equals the txid the input names. The txid commits to the outputs, so
the value, scriptPubKey and coinbase-ness Bend extracts are authenticated by the spending
transaction itself. NOT authenticated: the creating height the oracle reports (used only for
the coinbase-maturity rule), and that the output was still unspent before the start height
(double spends of pre-start outputs are not detectable without the genesis state).

Every such output is recorded in the `oracle_prevout` table, so nothing derived from it is
ever presented as genesis-verified.
"""
import re, struct, subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
LWD = HERE.parent / "follow/bin/follow-lwd"
HDR = 1487


def dummy_block(raw_tx):
    # A record blockdelta can parse: a header-shaped prefix (its checks are ignored here) and
    # one transaction. Only the tx line, its txid and its outputs are used.
    return bytes(140) + b"\xfd\x40\x05" + bytes(1344) + b"\x01" + raw_tx


def fetch(txids, log=print):
    """txid -> (height, [(vout, value, script)], is_coinbase), Bend-checked."""
    import sync
    want = sorted(set(txids))
    got = {}
    for i in range(0, len(want), 200):
        # follow-lwd takes and prints txids in internal byte order; blockdelta prints display order.
        rev = lambda t: bytes.fromhex(t)[::-1].hex()
        out = subprocess.run([str(LWD), "rawtx", *map(rev, want[i:i + 200])], capture_output=True, text=True).stdout
        for m in re.finditer(r"^rawtx ([0-9a-f]{64}) height (\d+) hex ([0-9a-f]+)$", out, re.M):
            got[rev(m.group(1))] = (int(m.group(2)), bytes.fromhex(m.group(3)))
    missing = [t for t in want if t not in got]
    if missing:
        raise ConnectionError(f"oracle did not return {len(missing)} prevout txs, e.g. {missing[0]}")
    recs = [(0, dummy_block(got[t][1])) for t in want]
    blocks = sync.run_blockdelta(recs, 6, "oracle")
    res = {}
    for t, b in zip(want, blocks):
        if "invalid" in b or len(b["txs"]) != 1:
            raise sync.Fail(f"oracle prevout tx {t}: rejected by the Bend wire validator")
        tx = b["txs"][0]
        if tx["txid"] != t:
            raise sync.Fail(f"oracle prevout tx {t}: Bend computes txid {tx['txid']}")
        res[t] = (got[t][0], tx["outs"], tx["cb"])
    return res


def prefill(blocks, st, log=print):
    """Insert the outputs these blocks spend that the store doesn't know (one transaction)."""
    import store as S
    st.db.execute("CREATE TABLE IF NOT EXISTS oracle_prevout(op BLOB PRIMARY KEY, height INTEGER) WITHOUT ROWID")
    created, need = set(), {}
    for b in blocks:
        for t in b["txs"]:
            for (ptx, n, _) in t["ins"]:
                if (ptx, n) not in created and st.utxo(ptx, n) is None:
                    need.setdefault(ptx, set()).add(n)
            for (k, _, _) in t["outs"]:
                created.add((t["txid"], k))
    if not need:
        return 0
    info = fetch(list(need), log)
    st.db.execute("BEGIN IMMEDIATE")
    n_ins = 0
    for ptx, vouts in need.items():
        h, outs, cb = info[ptx]
        by_k = {k: (v, s) for k, v, s in outs}
        for n in vouts:
            if n not in by_k:
                continue  # no such output: the store reports the input as missing
            op = S.op_key(ptx, n)
            if st.db.execute("SELECT 1 FROM oracle_prevout WHERE op=?", (op,)).fetchone():
                continue  # already prefilled once (and since spent): a double spend; the store fails it
            st.db.execute("INSERT OR IGNORE INTO utxo VALUES(?,?,?,?,?)", (op, by_k[n][0], by_k[n][1], h, int(cb)))
            st.db.execute("INSERT OR IGNORE INTO addr VALUES(?,?)", (by_k[n][1], op))
            st.db.execute("INSERT INTO oracle_prevout VALUES(?,?)", (op, h))
            n_ins += 1
    st.db.execute("COMMIT")
    return n_ins
