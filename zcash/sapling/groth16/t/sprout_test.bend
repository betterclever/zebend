# sprout_test <set_raw.bin>: for each Sprout record (kind 2) prints "hsig <hex>" and
# "in <9 inputs as 8 LE words, hex>" for t/sprout_test.py.
import Base
import ../../../halo2/lib/words.bend as Wd
import ../../../tx/blake2b.bend as B2
import ../sprout_inputs.bend as SI
import ../io.bend as IO2

def hexl(xs: +List<U32>) -> String:
  match xs:
    case Con{+x, t}:
      IO2.hex8(x) ++ " " ++ hexl(t)
    case Nil{}:
      ""

def rlen(+kind: U32) -> Nat:
  match kind:
    case 0:
      82n
    case 1:
      74n
    case _:
      126n

def one(+kind: U32, +raw: +List<U32>) -> IO(Unit):
  match kind:
    case 2:
      +bs = SI.bytes(raw)
      do IO<Unit>:
        IO.print("hsig " ++ hexl(B2.hash32(SI.pers(), List.append(&2, U32, SI.field(1n, bs), List.append(&2, U32, SI.field(2n, bs), List.append(&2, U32, SI.field(3n, bs), SI.field(8n, bs)))))))
        IO.print("in " ++ hexl(SI.inputs(raw)))
    case _:
      IO.pure(Unit, Unit{})

def go(fuel: Nat, +ws: +List<U32>) -> IO(Unit):
  match fuel ws:
    case 1n+k Con{+kind, _}:
      do IO<Unit>:
        one(kind, List.take(&2, U32, List.drop(&2, U32, ws, 50n), 76n))
        go(k, List.drop(&2, U32, ws, rlen(kind)))
    case _ _:
      IO.pure(Unit, Unit{})

def run(args: List<String>) -> IO(Unit):
  match args:
    case Con{_, Con{p, _}}:
      do IO<Unit>:
        bs : List<&2, U32> <- IO2.read_all(p)
        +ws : +List<U32> = IO2.pack4(bs)
        go(List.length(&2, U32, ws), ws)
    case _:
      IO.print("usage: sprout_test <set_raw.bin>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run(args)
