import Base
import ../blake2b.bend as B
import ../util.bend as U

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("c0 " ++ U.bhex(B.hash32(B.P.ZTxIdHeadersHash(), U.pattern(0))))
    IO.print("c1 " ++ U.bhex(B.hash32(B.P.ZTxIdHeadersHash(), U.pattern(3))))
    IO.print("c2 " ++ U.bhex(B.hash32(B.P.ZTxIdHeadersHash(), U.pattern(20))))
    IO.print("c3 " ++ U.bhex(B.hash32(B.P.Zcash_RedPallasH(), U.pattern(127))))
    IO.print("c4 " ++ U.bhex(B.hash64(B.P.Zcash_RedPallasH(), U.pattern(128))))
    IO.print("c5 " ++ U.bhex(B.hash32(B.P.ZTxIdOrcActMHash(), U.pattern(129))))
    IO.print("c6 " ++ U.bhex(B.hash64(B.P.ZTxIdOrcActMHash(), U.pattern(256))))
    IO.print("c7 " ++ U.bhex(B.hash32(B.P.ZTxIdOrcActMHash(), U.pattern(1000))))
    IO.print("c8 " ++ U.bhex(B.hash32(B.P.ZTxIdOrcActMHash(), U.pattern(8197))))
