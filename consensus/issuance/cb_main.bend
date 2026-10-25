# Check the coinbase transactions of sampled mainnet blocks against Zcash's issuance rules:
# founders' reward (pre-Canopy), funding streams with exact recipient scripts (Canopy, NU6,
# NU6.1) and the ZIP 271 one-time lockbox disbursement. Then sum the block subsidy over
# heights 1..3,146,400 and compare with zcashd's chain-supply checkpoint at that height.
import Base
import ./params.bend as P
import ./issuance.bend as I
import ./data.bend as D

def nth_s(xs: +List<String>, n: Nat) -> String:
  match xs n:
    case Con{h, _} 0n:
      h
    case Con{_, t} 1n+k:
      nth_s(t, k)
    case _ _:
      ""

def disbursement(n: Nat) -> +List<P.Out>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      P.Out{P.big(183, 1520984832), D.disbursement_script()} <> disbursement(p)

def fs_canopy(+h: Nat, +s: Nat) -> +List<P.Out>:
  [P.Out{I.fs_value(s, 7n), nth_s(D.bp_scripts(), I.address_index(I.canopy(), h))},
   P.Out{I.fs_value(s, 5n), D.zf_script()},
   P.Out{I.fs_value(s, 8n), D.mg_script()}]

def at_nu61(c: Bool) -> +List<P.Out>:
  match c:
    case True{}:
      disbursement(10n)
    case False{}:
      Nil{}

def fs_nu6(nu61: Bool, +h: Nat, +s: Nat) -> +List<P.Out>:
  match nu61:
    case True{}:
      P.Out{I.fs_value(s, 8n), D.zcg_script()} <> at_nu61(Nat.is_eq(h, U32.to_nat(3146400)))
    case False{}:
      [P.Out{I.fs_value(s, 8n), D.zcg_script()}]

def fs_post(canopy_era: Bool, +h: Nat, +s: Nat) -> +List<P.Out>:
  match canopy_era:
    case True{}:
      fs_canopy(h, s)
    case False{}:
      fs_nu6(Nat.is_ge(h, U32.to_nat(3146400)), h, s)

def expected_ge1(pre_canopy: Bool, +h: Nat) -> +List<P.Out>:
  match pre_canopy:
    case True{}:
      [P.Out{Nat.div(I.block_subsidy(h), 5n), nth_s(D.fr_scripts(), I.founders_index(h))}]
    case False{}:
      fs_post(Nat.is_lt(h, U32.to_nat(2726400)), h, I.block_subsidy(h))

def expected(+h: Nat) -> +List<P.Out>:
  match h:
    case 0n:
      Nil{}
    case 1n+_:
      expected_ge1(Nat.is_lt(h, I.canopy()), h)

# --- matching expected outputs against the coinbase's (as a multiset) ----------------

def same(+a: P.Out, +b: P.Out) -> Bool:
  P.Out{va, sa} = a
  P.Out{vb, sb} = b
  Bool.and(Nat.is_eq(va, vb), String.eq(sa, sb))

type Rm is Data:
  Rm{found: Bool, rest: +List<P.Out>}

def rm_keep(+x: P.Out, r: Rm) -> Rm:
  Rm{f, rest} = r
  Rm{f, x <> rest}

def rm_join(hit: Bool, +x: P.Out, rest: +List<P.Out>, r: Rm) -> Rm:
  match hit:
    case True{}:
      Rm{True{}, rest}
    case False{}:
      rm_keep(x, r)

# Removes the first output equal to e (if any).
def remove(xs: +List<P.Out>, +e: P.Out) -> Rm:
  match xs:
    case Nil{}:
      Rm{False{}, Nil{}}
    case Con{+x, +rest}:
      rm_join(same(x, e), x, rest, remove(rest, e))

def rm_found(r: Rm) -> Bool:
  Rm{f, _} = r
  f

def rm_rest(r: Rm) -> +List<P.Out>:
  Rm{_, rest} = r
  rest

def b2n(b: Bool) -> Nat:
  match b:
    case True{}:
      1n
    case False{}:
      0n

# How many expected outputs are present among the coinbase's outputs, each output used once.
def matched(es: +List<P.Out>, +outs: +List<P.Out>) -> Nat:
  match es:
    case Nil{}:
      0n
    case Con{+e, rest}:
      +r = remove(outs, e)
      Nat.add(b2n(rm_found(r)), matched(rest, rm_rest(r)))

# --- reporting -------------------------------------------------------------------------

type Tally is Data:
  Tally{blocks: Nat, ok: Nat, exp: Nat, hit: Nat}

def ok_str(c: Bool) -> String:
  match c:
    case True{}:
      "ok"
    case False{}:
      "MISSING"

def show_ok(+a: Nat, +b: Nat) -> String:
  ok_str(Nat.is_eq(a, b))

def line(+h: Nat, +n: Nat, +m: Nat) -> String:
  "block " ++ Nat.show(h) ++ ": expected outputs present " ++ Nat.show(m) ++ "/" ++ Nat.show(n) ++ " " ++ show_ok(n, m)

def tally_add(t: Tally, +n: Nat, +m: Nat) -> Tally:
  Tally{b, ok, e, x} = t
  Tally{1n+b, Nat.add(ok, b2n(Nat.is_eq(n, m))), Nat.add(e, n), Nat.add(x, m)}

def check(bs: +List<P.Block>, t: Tally) -> IO(Tally):
  match bs:
    case Nil{}:
      IO.pure(Tally, t)
    case Con{b, rest}:
      P.Block{+h, +outs} = b
      +es = expected(h)
      +n = List.length(&2, P.Out, es)
      +m = matched(es, outs)
      do IO<Tally>:
        IO.print(line(h, n, m))
        check(rest, tally_add(t, n, m))

# --- total issuance up to the zcashd supply checkpoint ------------------------------
# Runtime Nats stop at 2^48 and the total is ~2^50.5 zatoshi, so the sum is kept in units
# of 62,500 zat (= MaxBlockSubsidy / SlowStartInterval). Every block subsidy up to the
# checkpoint is a multiple of it; `odd` counts heights where that fails (must be 0).

type Sum is Data:
  Sum{units: Nat, odd: Nat}

def unit() -> Nat:
  U32.to_nat(62500)

def sum_add(s: Sum, +v: Nat) -> Sum:
  Sum{u, o} = s
  Sum{Nat.add(u, Nat.div(v, unit())), Nat.add(o, b2n(Nat.is_ne(Nat.mod(v, unit()), 0n)))}

def sum_go(n: Nat, +h: Nat, s: Sum) -> Sum:
  match n:
    case 0n:
      s
    case 1n+p:
      sum_go(p, 1n+h, sum_add(s, I.block_subsidy(h)))

# zcashd's nChainSupplyCheckpointTotalSupply at 3,146,400 = 26249412764 * 62500 + 54480.
def ck_q() -> Nat:
  P.big(6, 479608988)

def ck_r() -> Nat:
  U32.to_nat(54480)

def report_sum(s: Sum) -> IO(Unit):
  Sum{+u, +o} = s
  do IO<Unit>:
    IO.print("sum of block subsidies, heights 1..3146400: " ++ Nat.show(u) ++ " x 62500 zat (heights not a multiple of 62500: " ++ Nat.show(o) ++ ")")
    IO.print("zcashd supply checkpoint at 3146400:          " ++ Nat.show(ck_q()) ++ " x 62500 + " ++ Nat.show(ck_r()) ++ " zat")
    IO.print("issued >= supply: " ++ ok_str(Nat.is_gt(u, ck_q())) ++ ", difference " ++ Nat.show(Nat.sub(Nat.mul(Nat.sub(u, ck_q()), unit()), ck_r())) ++ " zat")

def report(t: Tally) -> IO(Unit):
  Tally{b, ok, e, x} = t
  do IO<Unit>:
    IO.print("blocks " ++ Nat.show(b) ++ ", all expected outputs present in " ++ Nat.show(ok) ++ " (" ++ Nat.show(x) ++ "/" ++ Nat.show(e) ++ " outputs)")
    report_sum(sum_go(U32.to_nat(3146400), 1n, Sum{0n, 0n}))

def main() -> IO(Unit):
  do IO<Unit>:
    t : Tally <- check(D.blocks(), Tally{0n, 0n, 0n, 0n})
    report(t)
