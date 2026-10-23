import Base
import ./planner.bend as P

# Demo: plan some migrations and print them.

def digit_of(r: Nat) -> P.Digit:
  match r:
    case 0n:
      P.D0{}
    case 1n+r1:
      match r1:
        case 0n:
          P.D1{}
        case 1n+r2:
          match r2:
            case 0n:
              P.D2{}
            case 1n+r3:
              match r3:
                case 0n:
                  P.D3{}
                case 1n+r4:
                  match r4:
                    case 0n:
                      P.D4{}
                    case 1n+r5:
                      match r5:
                        case 0n:
                          P.D5{}
                        case 1n+r6:
                          match r6:
                            case 0n:
                              P.D6{}
                            case 1n+r7:
                              match r7:
                                case 0n:
                                  P.D7{}
                                case 1n+r8:
                                  match r8:
                                    case 0n:
                                      P.D8{}
                                    case 1n+r9:
                                      P.D9{}

def digits.cons(d: P.Digit, last: Bool, rest: +List<P.Digit>) -> +List<P.Digit>:
  match last:
    case True{}:
      [d]
    case False{}:
      d <> rest

# Little-endian decimal digits of n; `fuel` bounds the digit count.
def digits(fuel: Nat, +n: Nat) -> +List<P.Digit>:
  match fuel:
    case 0n:
      []
    case 1n+f:
      digits.cons(digit_of(Nat.mod(n, 10n)), Nat.is_eq(Nat.div(n, 10n), 0n), digits(f, Nat.div(n, 10n)))

def zec(z: Nat) -> String:
  Nat.show(z) ++ " zat"

def show_outs(os: +List<P.Output>) -> String:
  match os:
    case Nil{}:
      ""
    case Con{o, t}:
      match o:
        case P.Output{pl, v}:
          "\n    Ironwood  " ++ zec(v) ++ show_outs(t)

def show_plan(m: Maybe<P.Plan>) -> String:
  match m:
    case None{}:
      "  no plan: the notes do not cover amount + fee"
    case Some{p}:
      match p:
        case P.Plan{+s, +o, c, f, b, sh, ca, fo}:
          "  spend " ++ zec(P.notes_total(s)) ++ " from " ++ Nat.show(P.n_spent(s)) ++ " Orchard note(s)" ++ "\n  " ++ Nat.show(P.n_outputs(o)) ++ " denominated outputs:" ++ show_outs(o) ++ "\n  change   Ironwood  " ++ zec(c) ++ "\n  fee      " ++ zec(f) ++ " (ZIP 317)"

def run(+notes: +List<P.Note>, +amount: Nat) -> String:
  "migrate " ++ zec(amount) ++ ":\n" ++ show_plan(P.plan(notes, digits(20n, amount)))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(run([P.Note{P.Orchard{}, 400000000n}], 314159265n))
    IO.print(run([P.Note{P.Orchard{}, 120000000n}, P.Note{P.Orchard{}, 90000000n}], 199990000n))
    IO.print(run([P.Note{P.Orchard{}, 100000n}], 99999n))
