# joinSplitSig verification: Ed25519 with ZIP 215 rules (consensus/gaps/ed25519, tested against
# ed25519-zebra 4.2.0: 62,830/62,830 verdicts incl. the 196 ZIP 215 small-order vectors).
import Base
import ../ed25519/ed25519.bend as Ed

def verify(+pk: +List<U32>, +sig: +List<U32>, +msg: +List<U32>) -> Bool:
  Ed.verify(pk, sig, msg)
