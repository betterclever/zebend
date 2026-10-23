import Base

def sum(xs: List<&2, U32>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      sum(t, (acc + h : U32))

def report(f: File, res: Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match res:
    case Done{bytes}:
      do IO<Unit>:
        File.close(f)
        IO.print("byte sum " ++ U32.show(sum(bytes, 0)))
    case Fail{e}:
      do IO<Unit>:
        File.close(f)
        IO.print("read failed")

def finish(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (f, res) = r
  report(f, res)

def main() -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open("/data/input.bin", "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 8388608)
    finish(r)
