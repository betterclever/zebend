# tv FILE.ztv: Zebend's transparent-input validation.
#   file   := "ZTV1" || count u32 || record*
#   record := height u32 || flags u32 || tx_len u32 || tx || n_prev u32 || (amount i64 || script_len u32 || scriptPubKey)*
# For each record prints "r <k> <verdicts>": one character per transparent input, 1 = the
# input's scriptSig satisfies the spent scriptPubKey (signatures, P2SH, CLTV, all of it) under
# the record's script flags, 0 = it does not. A transaction the wire validator rejects, or whose
# n_prev differs from its input count, prints "r <k> INVALID".
import Base
import ./util.bend as U
import ./sighash/sighash.bend as SH
import ./script/core.bend as C
import ./script/interp.bend as I
import ../wire/txv.bend as V

def is_ffff(+q: +List<U32>) -> Bool:
  U.eq(q, [255, 255, 255, 255])

def verdicts(ins: List<&2, SH.TxIn>, +i: Nat, +prevs: +List<U32>, +tx: SH.Tx, +flags: U32, +lock: U32) -> String:
  match ins:
    case Nil{}:
      ""
    case Con{+inp, t}:
      +k = U32.to_nat(U.u32_at(prevs, 8n))
      +spk = U.at(prevs, 12n, k)
      +ctx = {C.Ctx{tx, i, spk, U.take(prevs, 8n), lock, is_ffff(SH.in_seq(inp))} : C.Ctx}
      +v = I.verify_input(flags, SH.in_script(inp), spk, ctx)
      Bool.pick(String, v, "1", "0") ++ verdicts(t, 1n+i, U.drop(prevs, (12n + k : Nat)), tx, flags, lock)

def zeros_str(n: Nat) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      "0" ++ zeros_str(p)

# A v5/v6 transaction must carry the branch id of its height (Zebra rejects it otherwise).
def tx_body(ok: Bool, +tx: SH.Tx, +prevs: +List<U32>, +flags: U32) -> String:
  match ok:
    case True{}:
      verdicts(SH.tx_ins(tx), 0n, prevs, tx, flags, SH.tx_lock(tx))
    case False{}:
      zeros_str(SH.tx_nvin(tx))

def tx_parsed(+tx: SH.Tx, +height: U32, +nprev: U32, +prevs: +List<U32>, +flags: U32) -> String:
  +n_ok = Nat.is_eq(SH.tx_nvin(tx), U32.to_nat(nprev))
  +br_ok = U32.is_lt(SH.tx_ver(tx), 5) || U32.is_eq(SH.tx_branch(tx), SH.branch_of_height(height))
  Bool.pick(String, n_ok, tx_body(br_ok, tx, prevs, flags), "INVALID")

def tx_valid(ok: Bool, +xs: +List<U32>, +height: U32, +nprev: U32, +prevs: +List<U32>, +flags: U32) -> String:
  match ok:
    case True{}:
      tx_parsed(SH.parse(xs, height, prevs), height, nprev, prevs, flags)
    case False{}:
      "INVALID"

def prevs_len(n: Nat, +ps: +List<U32>, +acc: Nat) -> Nat:
  match n:
    case 0n:
      acc
    case 1n+p:
      +k = (12n + U32.to_nat(U.u32_at(ps, 8n)) : Nat)
      prevs_len(p, U.drop(ps, k), (acc + k : Nat))

type Step is Data:
  Step{line: String, rest: +List<U32>}

def record(+xs: +List<U32>, +k: U32) -> Step:
  +height = U.u32_at(xs, 0n)
  +flags = U.u32_at(xs, 4n)
  +txlen = U32.to_nat(U.u32_at(xs, 8n))
  +tx = U.at(xs, 12n, txlen)
  +after = U.drop(xs, (12n + txlen : Nat))
  +nprev = U.u32_at(after, 0n)
  +pr = U.drop(after, 4n)
  +plen = prevs_len(U32.to_nat(nprev), pr, 0n)
  +prevs = U.take(pr, plen)
  Step{"r " ++ U32.show(k) ++ " " ++ tx_valid(V.valid(tx), tx, height, nprev, prevs, flags) ++ "\n", U.drop(pr, plen)}

def st_line(s: Step) -> String:
  Step{l, _} = s
  l

def st_rest(s: Step) -> +List<U32>:
  Step{_, r} = s
  r

def go(n: Nat, +k: U32, +xs: +List<U32>) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      +st = record(xs, k)
      st_line(st) ++ go(p, (k + 1 : U32), st_rest(st))

def run(+bs: +List<U32>) -> String:
  Bool.pick(String, U.eq(U.take(bs, 4n), [90, 84, 86, 49]), go(U32.to_nat(U.u32_at(bs, 4n)), 0, U.drop(bs, 8n)), "bad file\n")

def path1(xs: List<String>) -> String:
  match xs:
    case Con{_, Con{a, _}}:
      a
    case _:
      ""

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    f : File <- IO.try(File, File.open(path1(args), "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(f, 200000000)
    IO.print(run(U.bytes_of(r)))
