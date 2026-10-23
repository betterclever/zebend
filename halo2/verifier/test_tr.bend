import Base
import ./vlib.bend as L

def W(+a: U32) -> L.U8w:
  L.U8w{a, (a * 3 : U32), (a * 5 : U32), (a * 7 : U32), (a * 11 : U32), (a * 13 : U32), (a * 17 : U32), (a .&. 268435455 : U32)}

def main() -> IO(Unit):
  +pr = {L.Proof{W(7) <> Nil{}, Nil{}, Nil{}} : L.Proof}
  +s0 = L.st_new(pr)
  +s1 = L.ab_scalar(s0, L.f_of_words(W(5)))
  +r1 = L.squeeze(s1)
  +s2 = L.lgf(L.sf_st(r1), "c1", L.sf_v(r1))
  +r2 = L.rd_scalar(s2)
  +s3 = L.ab_point(L.ab_point(L.sf_st(r2), L.VP{W(100), W(200)}), L.VP{W(300), W(400)})
  +r3 = L.squeeze(s3)
  +s4 = L.lgf(L.sf_st(r3), "c2", L.sf_v(r3))
  +s5 = L.ab_point(L.ab_point(L.ab_point(s4, L.VP{W(1000), W(2000)}), L.VP{W(3000), W(4000)}), L.VP{W(5000), W(6000)})
  +r5 = L.squeeze(s5)
  +s6 = L.lgf(L.sf_st(r5), "c3", L.sf_v(r5))
  do IO<Unit>:
    L.print_log(L.st_log(s6))
    IO.print("ok " ++ U32.show(L.st_ok(s6)))
