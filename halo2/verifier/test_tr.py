import hashlib
p=0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001
M=2**32
def W(a): return b"".join(((x%M)).to_bytes(4,"little") for x in [a,a*3,a*5,a*7,a*11,a*13,a*17,a&0x0fffffff])
h=hashlib.blake2b(digest_size=64, person=b"Halo2-Transcript")
def sq(name):
    h.update(b"\x00"); d=h.copy().digest()
    v=(int.from_bytes(d[:32],"little")+int.from_bytes(d[32:],"little")*2**256)%p
    print(name, v.to_bytes(32,"little").hex())
h.update(b"\x02"+W(5)); sq("c1")
h.update(b"\x02"+W(7))
for x,y in [(100,200),(300,400)]: h.update(b"\x01"+W(x)+W(y))
sq("c2")
for x,y in [(1000,2000),(3000,4000),(5000,6000)]: h.update(b"\x01"+W(x)+W(y))
sq("c3")
