import Base

# Nat algebra for the field proofs. Bend has no ring tactic, so associativity,
# commutativity and doubling are proven here once and used by rewriting.

law add_zero_r:
  for x: Nat
  {Nat.add(x, 0n) == x : Nat}

def add_zero_r(x):
  match x:
    case 0n:
      {==}
    case 1n+p:
      %add_zero_r(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}

law add_succ_r:
  for x: Nat
  for -y: Nat
  {Nat.add(x, 1n+y) == 1n+Nat.add(x, y) : Nat}

def add_succ_r(x, y):
  match x:
    case 0n:
      {==}
    case 1n+p:
      %add_succ_r(p, y) : {1n+Nat.add(p, 1n+y) == 1n+_ : Nat}
      {==}

law add_assoc:
  for x: Nat
  for -y: Nat
  for -z: Nat
  {Nat.add(Nat.add(x, y), z) == Nat.add(x, Nat.add(y, z)) : Nat}

def add_assoc(x, y, z):
  match x:
    case 0n:
      {==}
    case 1n+p:
      %add_assoc(p, y, z) : {1n+Nat.add(Nat.add(p, y), z) == 1n+_ : Nat}
      {==}

law add_comm:
  for x: Nat
  for +y: Nat
  {Nat.add(x, y) == Nat.add(y, x) : Nat}

def add_comm(x, y):
  match x:
    case 0n:
      Equal.sym(Nat, Nat.add(y, 0n), y, add_zero_r(y))
    case 1n+p:
      %Equal.sym(Nat, Nat.add(y, 1n+p), 1n+Nat.add(y, p), add_succ_r(y, p)) : {1n+Nat.add(p, y) == _ : Nat}
      %add_comm(p, y) : {1n+Nat.add(p, y) == 1n+_ : Nat}
      {==}

law double_add:
  for x: Nat
  for -y: Nat
  {Nat.double(Nat.add(x, y)) == Nat.add(Nat.double(x), Nat.double(y)) : Nat}

def double_add(x, y):
  match x:
    case 0n:
      {==}
    case 1n+p:
      %double_add(p, y) : {2n+Nat.double(Nat.add(p, y)) == 2n+_ : Nat}
      {==}

# (a + b) + (c + d) == (a + c) + (b + d)
law swap_mid:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +d: Nat
  {Nat.add(Nat.add(a, b), Nat.add(c, d)) == Nat.add(Nat.add(a, c), Nat.add(b, d)) : Nat}

def swap_mid(a, b, c, d):
  %Equal.sym(Nat, Nat.add(Nat.add(a, b), Nat.add(c, d)), Nat.add(a, Nat.add(b, Nat.add(c, d))), add_assoc(a, b, Nat.add(c, d))) : {_ == Nat.add(Nat.add(a, c), Nat.add(b, d)) : Nat}
  %Equal.sym(Nat, Nat.add(Nat.add(a, c), Nat.add(b, d)), Nat.add(a, Nat.add(c, Nat.add(b, d))), add_assoc(a, c, Nat.add(b, d))) : {Nat.add(a, Nat.add(b, Nat.add(c, d))) == _ : Nat}
  %add_assoc(b, c, d) : {Nat.add(a, _) == Nat.add(a, Nat.add(c, Nat.add(b, d))) : Nat}
  %add_assoc(c, b, d) : {Nat.add(a, Nat.add(Nat.add(b, c), d)) == Nat.add(a, _) : Nat}
  %add_comm(b, c) : {Nat.add(a, Nat.add(Nat.add(b, c), d)) == Nat.add(a, Nat.add(_, d)) : Nat}
  {==}
