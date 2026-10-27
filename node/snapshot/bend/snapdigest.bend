# Zebend snapshot: the state digest, in Bend.
#
# A snapshot section is a sequence of records, each a u32 LE length followed by that many
# payload bytes, sorted by payload (strictly increasing, bytewise). Its root is a binary
# Merkle tree with SHA-256 and RFC 6962 domain separation:
#   leaf  = SHA-256(0x00 || payload)
#   node  = SHA-256(0x01 || left || right)
#   level = pairs hashed left to right; an odd last node is carried up unchanged
#   root of no records = SHA-256("")
# (this pairing gives the same root as RFC 6962's largest-power-of-two split). Because the
# driver cuts a section into chunks of 2^k records, the root of the section equals the same
# tree built over the chunk roots ("nodes" mode), so chunks run as parallel processes.
#
# Usage:
#   snapdigest leaves FILE OFF LEN N SKIP
#       the LEN bytes at OFF hold SKIP (0 or 1) context records followed by N records. The
#       context record is the previous chunk's last record: it is only used for the order
#       check. Prints "n <N parsed>", "order OK|BAD" (strictly increasing payloads, including
#       against the context record), "exact OK|BAD" (the N records end exactly at OFF+LEN, and
#       no record runs past it), "root <hex>".
#   snapdigest nodes FILE OFF LEN N
#       N 32-byte nodes at OFF: prints "root <hex>" of the tree built over them (no leaf hash).
#   snapdigest hash FILE OFF LEN
#       prints "hash <hex>": SHA-256 of the bytes (the final digest of a snapshot's manifest).
import Base
import ../../../zcash/block/sha256.bend as S
import ../../../zcash/block/bytes.bend as Y
import ../../../zcash/block/util.bend as U

def bytes_of(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

# bytewise a < b (a proper prefix is smaller)
def lt(xs: +List<U32>, ys: +List<U32>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      False{}
    case Nil{} Con{_, _}:
      True{}
    case Con{_, _} Nil{}:
      False{}
    case Con{+x, xt} Con{+y, yt}:
      (x < y : U32) || (U32.is_eq(x, y) && lt(xt, yt))

def leaf(+rec: +List<U32>) -> +List<U32>:
  S.hash(0 <> rec)

def node(+a: +List<U32>, +b: +List<U32>) -> +List<U32>:
  S.hash(1 <> Y.append(a, b))

def level(xs: +List<+List<U32>>) -> +List<+List<U32>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{a, t}:
      match t:
        case Nil{}:
          a <> Nil{}
        case Con{b, rest}:
          node(a, b) <> level(rest)

def first(xs: +List<+List<U32>>) -> +List<U32>:
  match xs:
    case Nil{}:
      S.hash(Nil{})
    case Con{+h, _}:
      h

# 48 levels: more than enough for 2^32 nodes; a single node passes through unchanged.
def root(fuel: Nat, +xs: +List<+List<U32>>) -> +List<U32>:
  match fuel:
    case 0n:
      first(xs)
    case 1n+p:
      root(p, level(xs))

# ---------------------------------------------------------------- records

type P is Data:
  P{ok: Bool, exact: Bool, n: Nat, hs: +List<+List<U32>>}

# Parse n records; prev is the previous payload (has_prev False for the first one).
def recs(n: Nat, +xs: +List<U32>, +has_prev: Bool, +prev: +List<U32>, +ok: Bool, +exact: Bool, +k: Nat,
         acc: +List<+List<U32>>) -> P:
  match n:
    case 0n:
      P{ok, exact && U32.is_eq(Y.length(xs), 0), k, List.reverse(&2, +List<U32>, acc)}
    case 1n+m:
      +len = Y.get_le32(xs)
      +body = Y.drop(xs, 4n)
      +rec = Y.take(body, U32.to_nat(len))
      +fit = U32.is_eq(Y.length(Y.take(xs, 4n)), 4) && U32.is_eq(Y.length(rec), len)
      +ok2 = ok && (Bool.not(has_prev) || lt(prev, rec))
      recs(m, Y.drop(body, U32.to_nat(len)), True{}, rec, ok2, exact && fit, 1n+k, leaf(rec) <> acc)

# the optional context record: returns (has_prev, prev, rest)
type C is Data:
  C{has: Bool, prev: +List<U32>, rest: +List<U32>}

def ctx(skip: Nat, +xs: +List<U32>) -> C:
  match skip:
    case 0n:
      C{False{}, Nil{}, xs}
    case 1n+_:
      +len = Y.get_le32(xs)
      +body = Y.drop(xs, 4n)
      C{True{}, Y.take(body, U32.to_nat(len)), Y.drop(body, U32.to_nat(len))}

def ok_s(b: Bool) -> String:
  match b:
    case True{}:
      "OK"
    case False{}:
      "BAD"

def leaves_out(p: P) -> IO(Unit):
  P{ok, exact, n, +hs} = p
  do IO<Unit>:
    IO.print("n " ++ Nat.show(n))
    IO.print("order " ++ ok_s(ok))
    IO.print("exact " ++ ok_s(exact))
    IO.print("root " ++ U.bhex(root(48n, hs)))

def leaves_c(+n: U32, c: C) -> IO(Unit):
  C{+has, +prev, +rest} = c
  leaves_out(recs(U32.to_nat(n), rest, has, prev, True{}, True{}, 0n, Nil{}))

def run_leaves(+n: U32, +skip: U32, +bs: +List<U32>) -> IO(Unit):
  leaves_c(n, ctx(U32.to_nat(skip), bs))

def nodes_rev(n: Nat, +bs: +List<U32>, acc: +List<+List<U32>>) -> +List<+List<U32>>:
  match n:
    case 0n:
      acc
    case 1n+p:
      nodes_rev(p, Y.drop(bs, 32n), Y.take(bs, 32n) <> acc)

def run_nodes(+n: U32, +bs: +List<U32>) -> IO(Unit):
  IO.print("root " ++ U.bhex(root(48n, List.reverse(&2, +List<U32>, nodes_rev(U32.to_nat(n), bs, Nil{})))))

def run_hash(+bs: +List<U32>) -> IO(Unit):
  IO.print("hash " ++ U.bhex(S.hash(bs)))

# ---------------------------------------------------------------- IO

def or_zero(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}:
      v
    case None{}:
      0

def num(s: String) -> U32:
  or_zero(U32.read(s))

type Args is Type:
  Args{mode: String, path: String, off: String, len: String, n: String, skip: String}

def args_of(xs: List<String>) -> Args:
  match xs:
    case Con{_, Con{m, Con{p, Con{o, Con{l, Con{n, Con{s, _}}}}}}}:
      Args{m, p, o, l, n, s}
    case Con{_, Con{m, Con{p, Con{o, Con{l, Con{n, Nil{}}}}}}}:
      Args{m, p, o, l, n, "0"}
    case Con{_, Con{m, Con{p, Con{o, Con{l, Nil{}}}}}}:
      Args{m, p, o, l, "0", "0"}
    case _:
      Args{"usage", "", "0", "0", "0", "0"}

def dispatch(+is_leaves: Bool, +is_nodes: Bool, +n: U32, +skip: U32, +bs: +List<U32>) -> IO(Unit):
  match is_leaves:
    case True{}:
      run_leaves(n, skip, bs)
    case False{}:
      match is_nodes:
        case True{}:
          run_nodes(n, bs)
        case False{}:
          run_hash(bs)

def run(a: Args) -> IO(Unit):
  Args{+m, p, os, ls, ns, ss} = a
  do IO<Unit>:
    f : File <- IO.try(File, File.open(p, "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_at(f, num(os), num(ls))
    dispatch(String.eq(m, "leaves"), String.eq(m, "nodes"), num(ns), num(ss), bytes_of(r))

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    run(args_of(xs))
