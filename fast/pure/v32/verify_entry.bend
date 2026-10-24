# Pure entry point for the JavaScript / browser build: no IO, so `-o verify.mjs`
# exports it and a page can call it with the bytes it already holds.
import Base
import ../../../halo2/lib/words.bend as Wd
import ../lib32/vesta.bend as V
import ./vlib.bend as L
import ./orchard_dyn.bend as O
import ./bundle_main.bend as B

# params_g.bin bytes, bundle bytes -> 1 (valid proof) or 0
def verify(gb: +List<U32>, bb: +List<U32>) -> U32:
  +inp : B.In = B.parse_bundle(bb)
  +st : L.St = O.verify(B.in_pr(inp), B.points(B.items(L.pack4(gb))), B.in_np(inp), B.in_ni(inp))
  L.st_ok(st)

# Same, with G already packed into 2048 point encodings (8 LE U32 words each) by the
# caller, and the bundle into LE U32 words; keeps the JS call depth browser-sized.
def verify_w(gws: +List<Wd.W>, +bws: +List<U32>) -> U32:
  +np = U32.to_nat(B.w_at(0n, bws))
  +ni = U32.to_nat(B.w_at(1n, bws))
  +nitems = U32.to_nat((B.w_at(2n, bws) / 32 : U32))
  +all : +List<Wd.W> = B.items(List.drop(&2, U32, bws, 3n))
  +pr : L.Proof = L.Proof{List.take(&2, Wd.W, all, nitems), B.fps(List.drop(&2, Wd.W, all, nitems))}
  L.st_ok(O.verify(pr, B.points(gws), np, ni))
