# Zebend P2P: connect to a live Zcash mainnet peer, handshake, and download block
# headers, verifying each header's SHA-256d hash and prev-hash linkage in Bend.
#
#   ./zebend-p2p [peer-ip|-] [protocol] [start-height] [start-hash] [batches] [check-height] [check-hash]
#
# Defaults start from Zebra's mainnet checkpoint 3,522,060 and fetch 3 batches, so the
# header at checkpoint 3,522,460 is checked against Zebra's published hash.
import Base
import ./bytes.bend as B
import ./msg.bend as M
import ./node.bend as N

type Next is Type:
  Next{sock: Socket, buf: +List<U32>, acc: N.Acc, cont: Bool}

def DNS.resolve(host: String) -> IO(Result<&1, &1, U32 & String, String>):
  import "./dns.c"
  import "./dns.js"

def Clock.unix() -> IO(U32):
  import "./clock.c"
  import "./clock.js"

def fst_sock(r: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>) -> Socket:
  (s, _) = r
  s

def send_all(fs: +List<+List<U32>>, sock: Socket) -> IO(Socket):
  match fs:
    case Nil{}:
      IO.pure(Socket, sock)
    case Con{f, t}:
      IO.bind(Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>, Socket,
        TCP.send_bytes(sock, f), r => send_all(t, fst_sock(r)))

def print_lines(xs: +List<String>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{l, t}:
      IO.bind(Unit, Unit, IO.print(l), _ => print_lines(t))

def outs_of(+acc: N.Acc) -> +List<String>:
  N.Acc{_, _, outs} = acc
  List.reverse(&2, String, outs)

def sends_of(+acc: N.Acc) -> +List<+List<U32>>:
  N.Acc{_, sends, _} = acc
  List.reverse(&2, +List<U32>, sends)

def cleared(acc: N.Acc) -> N.Acc:
  N.Acc{st, _, _} = acc
  N.Acc{st, Nil{}, Nil{}}

def after_drain(sock: Socket, d: N.Drained) -> Next:
  N.Drained{buf, +acc} = d
  Next{sock, buf, acc, Bool.not(N.is_finished(acc))}

def decide_bytes(sock: Socket, m: Maybe<&1, List<&2, U32>>, +buf: +List<U32>, acc: N.Acc) -> Next:
  match m:
    case None{}:
      Next{sock, buf, N.say(acc, "!! peer closed the connection"), False{}}
    case Some{bytes}:
      after_drain(sock, N.drain(64n, M.parse(B.append(buf, bytes)), acc))

def err_text(e: U32 & String) -> String:
  (code, text) = e
  text ++ " (errno " ++ U32.show(code) ++ ")"

def decide_res(sock: Socket, res: Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, +buf: +List<U32>, acc: N.Acc) -> Next:
  match res:
    case Fail{e}:
      Next{sock, buf, N.say(acc, "!! receive failed: " ++ err_text(e)), False{}}
    case Done{m}:
      decide_bytes(sock, m, buf, acc)

def decide(r: Socket & Poll<&1, &1, Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, Unit>, +buf: +List<U32>, acc: N.Acc) -> Next:
  (sock, poll) = r
  match poll:
    case Wait{_}:
      Next{sock, buf, acc, True{}}
    case Ready{res}:
      decide_res(sock, res, buf, acc)

# Print pending log lines, send pending frames, wait up to 5 s for bytes, and handle them.
def emit_recv(nx: Next) -> IO(Next):
  Next{sock, buf, +acc, _} = nx
  do IO<Next>:
    print_lines(outs_of(acc))
    s2 : Socket <- send_all(sends_of(acc), sock)
    r : Socket & Poll<&1, &1, Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>, Unit> <- TCP.try_recv_bytes(s2, 1048576, 5000)
    return decide(r, buf, cleared(acc))

def finish_io(nx: Next) -> IO(N.Acc):
  Next{sock, _, +acc, _} = nx
  do IO<N.Acc>:
    print_lines(outs_of(acc))
    Socket.close(sock)
    return cleared(acc)

def loop(fuel: Nat, nx: Next) -> IO(N.Acc):
  match fuel:
    case 0n:
      finish_io(nx)
    case 1n+p:
      match nx:
        case Next{sock, buf, acc, cont}:
          match cont:
            case False{}:
              finish_io(Next{sock, buf, acc, False{}})
            case True{}:
              IO.bind(Next, N.Acc, emit_recv(Next{sock, buf, acc, True{}}), nx2 => loop(p, nx2))

# ---- peer selection -------------------------------------------------------

def ok_or_empty(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{s}:
      s
    case Fail{_}:
      ""

# ---- arguments ------------------------------------------------------------

def resolve_or_empty(host: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, String>, String, DNS.resolve(host), r => IO.pure(String, ok_or_empty(r)))

def arg_sel(m: Maybe<&2, String>, dflt: String) -> String:
  match m:
    case Some{+s}:
      Bool.pick(String, String.eq(s, "-"), dflt, s)
    case None{}:
      dflt

def arg(+args: +List<String>, n: Nat, dflt: String) -> String:
  arg_sel(List.get(&2, String, args, n), dflt)

def num_sel(m: Maybe<&2, U32>, dflt: U32) -> U32:
  match m:
    case Some{v}:
      v
    case None{}:
      dflt

def num(s: String, dflt: U32) -> U32:
  num_sel(U32.read(s), dflt)

def hash_arg(s: String) -> +List<U32>:
  B.reverse(B.of_hex(s))

# ---- output files ---------------------------------------------------------

def raw_then(h: N.Hdr, rest: +List<U32>) -> +List<U32>:
  N.Hdr{_, raw, _} = h
  B.append(raw, rest)

def raws_concat(hs: +List<N.Hdr>) -> +List<U32>:
  match hs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      raw_then(h, raws_concat(t))

def height_line(h: N.Hdr) -> String:
  N.Hdr{ht, _, hash} = h
  U32.show(ht) ++ " " ++ B.hex_rev(hash) ++ "\n"

def heights_text(hs: +List<N.Hdr>) -> String:
  match hs:
    case Nil{}:
      ""
    case Con{h, t}:
      height_line(h) ++ heights_text(t)

def close_pair(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, _) = r
  File.close(f)

def write_file(path: String, data: +List<U32>) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, data)
    close_pair(r)

def stored_of(+acc: N.Acc) -> +List<N.Hdr>:
  N.Acc{st, _, _} = acc
  N.St{_, _, _, _, _, _, s, _, _, _, _} = st
  List.reverse(&2, N.Hdr, s)

def summary(+acc: N.Acc) -> String:
  N.Acc{st, _, _} = acc
  N.St{_, _, h, _, _, _, _, l, c, a, _} = st
  "summary: " ++ U32.show(l) ++ " headers linked and hashed in Bend, tip #" ++ U32.show(h)
    ++ ", checkpoints matched: " ++ U32.show(c) ++ ", peer addresses learned: " ++ U32.show(a)

def finish_run(+acc: N.Acc) -> IO(Unit):
  +hs = stored_of(acc)
  do IO<Unit>:
    IO.print(summary(acc))
    write_file("out/headers.bin", raws_concat(hs))
    write_file("out/heights.txt", B.of_string(heights_text(hs)))
    IO.print("wrote out/headers.bin (raw headers, oldest first) and out/heights.txt")

def shareable(xs: List<String>) -> +List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      h <> shareable(t)

def linked_of(+acc: N.Acc) -> U32:
  N.Acc{st, _, _} = acc
  N.St{_, _, _, _, _, _, _, l, _, _, _} = st
  l

def done_sel(none: Bool, acc: N.Acc, +ip: String, next: IO(Unit)) -> IO(Unit):
  match none:
    case True{}:
      IO.bind(Unit, Unit, IO.print("   no headers from " ++ ip ++ "; trying the next peer"), _ => next)
    case False{}:
      finish_run(acc)

def done_or(+acc: N.Acc, +ip: String, next: IO(Unit)) -> IO(Unit):
  done_sel(U32.is_eq(linked_of(acc), 0), acc, ip, next)

def start_acc(+ip: String, +proto: U32, +now: U32, +nonce: U32, +h0: U32, +loc: +List<U32>, +batches: U32, +ch: U32, +cx: +List<U32>) -> N.Acc:
  +st = {N.St{proto, loc, h0, batches, ch, cx, Nil{}, 0, 0, 0, False{}} : N.St}
  {N.Acc{st, [M.frame("version", M.version_payload(proto, now, nonce, ip, 0))],
    ["connected to " ++ ip ++ ":8233\n-> version (protocol " ++ U32.show(proto) ++ ", /Zebend:0.1.0/)"]} : N.Acc}

def attempt_res(r: Result<&1, &1, U32 & String, Socket>, +ip: String, next: IO(Unit), +acc0: N.Acc) -> IO(Unit):
  match r:
    case Done{sock}:
      IO.bind(N.Acc, Unit, loop(400n, Next{sock, Nil{}, acc0, True{}}), a => done_or(a, ip, next))
    case Fail{e}:
      IO.bind(Unit, Unit, IO.print("   " ++ ip ++ ": " ++ err_text(e)), _ => next)

def attempt(m: Maybe<&1, Result<&1, &1, U32 & String, Socket>>, +ip: String, next: IO(Unit), +acc0: N.Acc) -> IO(Unit):
  match m:
    case Some{r}:
      attempt_res(r, ip, next, acc0)
    case None{}:
      IO.bind(Unit, Unit, IO.print("   " ++ ip ++ ": no answer in 5 s"), _ => next)

# Try peers in order until one session yields headers.
def try_peers(ips: +List<String>, +proto: U32, +now: U32, +nonce: U32, +h0: U32, +loc: +List<U32>, +batches: U32, +ch: U32, +cx: +List<U32>) -> IO(Unit):
  match ips:
    case Nil{}:
      IO.print("no mainnet peer completed a session")
    case Con{+ip, t}:
      IO.bind(Maybe<&1, Result<&1, &1, U32 & String, Socket>>, Unit,
        IO.within(Result<&1, &1, U32 & String, Socket>, 5000, TCP.connect(ip, 8233)),
        m => attempt(m, ip, try_peers(t, proto, now, nonce, h0, loc, batches, ch, cx),
          start_acc(ip, proto, now, nonce, h0, loc, batches, ch, cx)))

def main() -> IO(Unit):
  do IO<Unit>:
    args1 : List<String> <- IO.args()
    +args : +List<String> = shareable(args1)
    +peer : String = arg(args, 1n, "-")
    +proto : U32 = num(arg(args, 2n, "170190"), 170190)
    +h0 : U32 = num(arg(args, 3n, "3522060"), 3522060)
    +loc : +List<U32> = hash_arg(arg(args, 4n, "00000000000705964fc4c75da9cce97978197b666c9dcdfc1bcf8d44cd776e4d"))
    +batches : U32 = num(arg(args, 5n, "3"), 3)
    +ch : U32 = num(arg(args, 6n, "3522460"), 3522460)
    +cx : +List<U32> = hash_arg(arg(args, 7n, "000000000045b3f5233ab807e6ca23c991b92fe6726cb268793452af3e22f4f9"))
    IO.print("Zebend P2P: Zcash mainnet, in Bend")
    s1 : String <- resolve_or_empty("mainnet.seeder.zfnd.org")
    s2 : String <- resolve_or_empty("dnsseed.z.cash")
    +ips : +List<String> = Bool.pick(+List<String>, String.eq(peer, "-"), String.split(s1 ++ "," ++ s2, ','), [peer])
    IO.print("DNS seeds resolved: " ++ Nat.show(List.length(&2, String, ips)) ++ " addresses")
    now : U32 <- Clock.unix()
    nonce : U32 <- IO.try(U32, IO.random_u32())
    try_peers(ips, proto, now, nonce, h0, loc, batches, ch, cx)
