import socket, struct, hashlib, time, sys
def dsha(b): return hashlib.sha256(hashlib.sha256(b).digest()).digest()
def frame(cmd, p): return bytes.fromhex("24e92764") + cmd.encode().ljust(12, b"\0") + struct.pack("<I", len(p)) + dsha(p)[:4] + p
def netaddr(ip, port): return struct.pack("<Q", 0) + b"\0"*10 + b"\xff\xff" + socket.inet_aton(ip) + struct.pack(">H", port)
def version(proto, ip):
    ua = b"/probe:0.1/"
    return struct.pack("<iQq", proto, 0, int(time.time())) + netaddr(ip, 8233) + netaddr("0.0.0.0", 0) + struct.pack("<Q", 12345) + bytes([len(ua)]) + ua + struct.pack("<i", 0) + b"\0"
ip, proto = sys.argv[1], int(sys.argv[2])
s = socket.create_connection((ip, 8233), timeout=8)
s.sendall(frame("version", version(proto, ip)))
buf = b""
try:
    while len(buf) < 4000:
        d = s.recv(65536)
        if not d: break
        buf += d
except Exception as e: print("exc", e)
i = 0
while i + 24 <= len(buf):
    cmd = buf[i+4:i+16].rstrip(b"\0").decode(); n = struct.unpack("<I", buf[i+16:i+20])[0]
    p = buf[i+24:i+24+n]
    extra = ""
    if cmd == "version":
        v = struct.unpack("<i", p[:4])[0]; l = p[80]; ua = p[81:81+l]; h = struct.unpack("<i", p[81+l:85+l])[0]
        extra = f"proto={v} ua={ua} height={h}"
    if cmd == "reject": extra = p[:120]
    print(cmd, n, extra); i += 24 + n
print("total bytes", len(buf))
