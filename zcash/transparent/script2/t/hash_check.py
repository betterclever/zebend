#!/usr/bin/env python3
"""hash_t vs hashlib (sha1, sha256) and a reference RIPEMD-160 (hashlib if available, else
the pure-Python one in this file, itself checked on the standard test vectors)."""
import hashlib, os, random, struct, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
def rmd_py(m):
    try:
        return hashlib.new("ripemd160", m).digest()
    except ValueError:
        pass
    # pure-Python reference (RIPEMD-160 spec)
    r=[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,7,4,13,1,10,6,15,3,12,0,9,5,2,14,11,8,3,10,14,4,9,15,8,1,2,7,0,6,13,11,5,12,1,9,11,10,0,8,12,4,13,3,7,15,14,5,6,2,4,0,5,9,7,12,2,10,14,1,3,8,11,6,15,13]
    rr=[5,14,7,0,9,2,11,4,13,6,15,8,1,10,3,12,6,11,3,7,0,13,5,10,14,15,8,12,4,9,1,2,15,5,1,3,7,14,6,9,11,8,12,2,10,0,4,13,8,6,4,1,3,11,15,0,5,12,2,13,9,7,10,14,12,15,10,4,1,5,8,7,6,2,13,14,0,3,9,11]
    s=[11,14,15,12,5,8,7,9,11,13,14,15,6,7,9,8,7,6,8,13,11,9,7,15,7,12,15,9,11,7,13,12,11,13,6,7,14,9,13,15,14,8,13,6,5,12,7,5,11,12,14,15,14,15,9,8,9,14,5,6,8,6,5,12,9,15,5,11,6,8,13,12,5,12,13,14,11,8,5,6]
    ss=[8,9,9,11,13,15,15,5,7,7,8,11,14,14,12,6,9,13,15,7,12,8,9,11,7,7,12,7,6,15,13,11,9,7,15,11,8,6,6,14,12,13,5,14,13,13,7,5,15,5,8,11,14,14,6,14,6,9,12,9,12,5,15,8,8,5,12,9,12,5,14,6,8,13,6,5,15,13,11,11]
    K=[0,0x5A827999,0x6ED9EBA1,0x8F1BBCDC,0xA953FD4E]; KK=[0x50A28BE6,0x5C4DD124,0x6D703EF3,0x7A6D76E9,0]
    M=0xffffffff
    rol=lambda x,n:((x<<n)|(x>>(32-n)))&M
    def f(j,x,y,z):
        return [x^y^z,(x&y)|(~x&z),(x|~y)^z,(x&z)|(y&~z),x^(y|~z)][j]&M
    h=[0x67452301,0xEFCDAB89,0x98BADCFE,0x10325476,0xC3D2E1F0]
    ml=len(m)*8
    m=m+b"\x80"+b"\x00"*((55-len(m))%64)+struct.pack("<Q",ml)
    for o in range(0,len(m),64):
        X=struct.unpack("<16I",m[o:o+64])
        a,b,c,d,e=h; A,B,C,D,E=h
        for j in range(80):
            t=(rol((a+f(j//16,b,c,d)+X[r[j]]+K[j//16])&M,s[j])+e)&M; a,e,d,c,b=e,d,rol(c,10),b,t
            t=(rol((A+f(4-j//16,B,C,D)+X[rr[j]]+KK[j//16])&M,ss[j])+E)&M; A,E,D,C,B=E,D,rol(C,10),B,t
        t=(h[1]+c+D)&M; h[1]=(h[2]+d+E)&M; h[2]=(h[3]+e+A)&M; h[3]=(h[4]+a+B)&M; h[4]=(h[0]+b+C)&M; h[0]=t
    return struct.pack("<5I",*h)
assert rmd_py(b"").hex()=="9c1185a5c5e9fc54612808977ee8f548b2258d31"
assert rmd_py(b"abc").hex()=="8eb208f7e05d987a9b044a8e98c6b087f15a0bfc"
assert rmd_py(b"a"*1000000)[:4].hex()=="52783243"
random.seed(1)
msgs=[b"", b"abc", b"a"*55, b"a"*56, b"a"*63, b"a"*64, b"a"*65, b"a"*119, b"a"*120]+[os.urandom(random.randrange(0,600)) for _ in range(int(sys.argv[1]) if len(sys.argv)>1 else 500)]
path=os.path.join(HERE,"../../data/t/hash.bin")
with open(path,"wb") as fh:
    for m in msgs: fh.write(struct.pack("<I",len(m))+m)
out=subprocess.run([os.path.join(HERE,"hash_t"),path],capture_output=True,text=True).stdout.strip().split("\n")
assert len(out)==len(msgs),(len(out),len(msgs))
bad=0
for m,l in zip(msgs,out):
    s=hashlib.sha256(m).digest()
    want=" ".join([rmd_py(m).hex(),hashlib.sha1(m).hexdigest(),s.hex(),rmd_py(s).hex(),hashlib.sha256(s).hexdigest()])
    if l!=want:
        bad+=1
        if bad<4: print("MISMATCH len",len(m),"\n got ",l,"\n want",want)
print(f"{len(msgs)} messages x 5 hashes, {bad} mismatches")
