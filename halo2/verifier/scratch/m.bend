import Base

type Pair2 is Data:
  Pair2{a: U32, b: U32}

def mk(x: U32) -> Pair2:
  Pair2{x, 7}

def fst(p: Pair2) -> U32:
  Pair2{+a, _} = p
  a
