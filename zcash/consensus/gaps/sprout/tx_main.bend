# tx_main TXS [RECS]: (RECS: also write the Groth16 raw-field proof records, see stx.bend)
# tx_main TXS: every transaction of a batch file, in parallel. TXS = u32 count, then per tx:
#   u32 height | u32 len | raw tx | u32 ctx_len | ctx
# ctx (v5 with transparent inputs only, else empty) = zcash/tx's format: u32 len || spent
# amounts (i64 LE each) || u32 len || spent scriptPubKeys (CompactSize-prefixed).
# Prints per tx: "i v txid sighash n_spends n_outputs vb_lo vb_hi verdicts" (stx.bend `line`;
# verdicts = per-signature RedJubjub, spend-auth then binding, 1 = valid).
import Base
import ../../../tx/tx.bend as NT
import ./stx.bend as X

type Rec is Data:
  Rec{height: U32, tx: +List<U32>, ctx: +List<U32>}

# Linear record parsing (one pass over the byte list; no positional access into it).
type PS is Data:
  PS{xs: +List<U32>, rest: +List<U32>}

def split(n: Nat, xs: +List<U32>, acc: +List<U32>) -> PS:
  match n xs:
    case 1n+p Con{h, t}:
      split(p, t, h <> acc)
    case _ _:
      PS{List.reverse(&2, U32, acc), xs}

def le4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32)

type RR is Data:
  RR{rec: Maybe<&2, Rec>, rest: +List<U32>}

def rd_ctx(+h: U32, tx: +List<U32>, p: PS) -> RR:
  PS{ctx, rest} = p
  RR{Some{Rec{h, tx, ctx}}, rest}

def rd_tx(+h: U32, p: PS) -> RR:
  PS{tx, rest} = p
  match rest:
    case Con{a, Con{b, Con{c, Con{d, r2}}}}:
      rd_ctx(h, tx, split(U32.to_nat(le4(a, b, c, d)), r2, Nil{}))
    case _:
      RR{None{}, Nil{}}

def read_one(xs: +List<U32>) -> RR:
  match xs:
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, rest}}}}}}}}:
      rd_tx(le4(a, b, c, d), split(U32.to_nat(le4(e, f, g, h)), rest, Nil{}))
    case _:
      RR{None{}, Nil{}}

def push(m: Maybe<&2, Rec>, acc: +List<Rec>) -> +List<Rec>:
  match m:
    case Some{r}:
      r <> acc
    case None{}:
      acc

def recs(fuel: Nat, st: RR, acc: +List<Rec>) -> +List<Rec>:
  match fuel st:
    case 0n RR{m, _}:
      List.reverse(&2, Rec, push(m, acc))
    case 1n+k RR{m, rest}:
      recs(k, read_one(rest), push(m, acc))

def ctx_amounts(+c: +List<U32>) -> +List<U32>:
  NT.at(c, 4n, U32.to_nat(NT.u32_at(c, 0n)))

def ctx_scripts(+c: +List<U32>) -> +List<U32>:
  +alen = U32.to_nat(NT.u32_at(c, 0n))
  +spos = (alen + 4n : Nat)
  NT.at(c, (spos + 4n : Nat), U32.to_nat(NT.u32_at(c, spos)))

type Out is Data:
  Out{line: String, recs: +List<U32>}

def one(+i: Nat, r: Rec) -> Out:
  Rec{+h, +tx, +ctx} = r
  +res = X.run(tx, h, ctx_amounts(ctx), ctx_scripts(ctx))
  Out{Nat.show(i) ++ " " ++ X.line(res), X.recs_of(res)}

# Balanced fork-join over the records: lines in input order.
def all(+fuel: Nat, +cnt: Nat, +i0: Nat, +xs: +List<Rec>) -> +List<Out>:
  match fuel cnt xs:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+x, _}:
      one(i0, x) <> Nil{}
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a b = all(f, h, i0, List.take(&2, Rec, xs, h)) all(f, Nat.sub(cnt, h), (i0 + h : Nat), List.drop(&2, Rec, xs, h))
      List.append(&2, Out, a, b)
    case _ _ _:
      Nil{}

def out_line(o: Out) -> String:
  Out{l, _} = o
  l

def show(xs: +List<Out>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{o, t}:
      do IO<Unit>:
        IO.print(out_line(o))
        show(t)

def all_recs(xs: +List<Out>) -> +List<U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{Out{_, r}, t}:
      List.append(&2, U32, r, all_recs(t))

def close_w(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (g, _) = r
  File.close(g)


def write_recs(xs: List<String>, +out: +List<Out>) -> IO(Unit):
  match xs:
    case Con{q, _}:
      do IO<Unit>:
        g : File <- IO.try(File, File.open(q, "w"))
        r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(g, all_recs(out))
        close_w(r)
    case _:
      IO.pure(Unit, Unit{})

def bytes_of(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> +List<U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{p, rest}}:
      do IO<Unit>:
        f : File <- IO.try(File, File.open(p, "r"))
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 268435456)
        +bs : +List<U32> = bytes_of(r)
        +n : Nat = U32.to_nat(NT.u32_at(bs, 0n))
        +rs : +List<Rec> = recs(n, RR{None{}, List.drop(&2, U32, bs, 4n)}, Nil{})
        t0x : Nat <- IO.now()
        +t0 : Nat = t0x
        +out : +List<Out> = all(32n, n, 0n, rs)
        +len : Nat = List.length(&2, Out, out)
        t1x : Nat <- IO.now()
        +t1 : Nat = t1x
        show(out)
        write_recs(rest, out)
        IO.print("TOTAL txs " ++ Nat.show(len) ++ " ms " ++ Nat.show(Nat.sub(t1, t0)))
    case _:
      IO.print("usage: tx_main TXS")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args)
