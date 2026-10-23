# The pure half of the P2P client: given a received message and the session state,
# decide what to send and what to log. The IO loop (main.bend) only moves bytes.
import Base
import ./bytes.bend as B
import ./sha256.bend as H
import ./msg.bend as M

# A Zcash block header as received (140 fixed bytes + CompactSize + Equihash
# solution; 1487 bytes on mainnet) with its SHA-256d hash (internal byte order).
type Hdr is Data:
  Hdr{+height: U32, raw: +List<U32>, hash: +List<U32>}

type St is Data:
  St{+proto: U32, +expect: +List<U32>, +height: U32, +batches: U32,
     +check_h: U32, +check_hash: +List<U32>, +stored: +List<Hdr>,
     +linked: U32, +checked: U32, +addrs: U32, +finished: Bool}

# Session accumulator: state, frames to send (newest first), log lines (newest first).
type Acc is Data:
  Acc{st: St, sends: +List<+List<U32>>, outs: +List<String>}

type Compact2 is Data:
  C2{+value: U32, +width: U32}

# Handle every complete message in the buffer (at most `n`).
type Drained is Data:
  Drained{buf: +List<U32>, acc: Acc}

def u(+x: U32) -> String:
  U32.show(x)

def say(acc: Acc, line: String) -> Acc:
  Acc{st, sends, outs} = acc
  Acc{st, sends, line <> outs}

def send(acc: Acc, cmd: String, +payload: +List<U32>) -> Acc:
  Acc{st, sends, outs} = acc
  Acc{st, M.frame(cmd, payload) <> sends, outs}

def proto_of(+acc: Acc) -> U32:
  Acc{st, _, _} = acc
  St{proto, _, _, _, _, _, _, _, _, _, _} = st
  proto

def expect_of(+acc: Acc) -> +List<U32>:
  Acc{st, _, _} = acc
  St{_, expect, _, _, _, _, _, _, _, _, _} = st
  expect

def height_of(+acc: Acc) -> U32:
  Acc{st, _, _} = acc
  St{_, _, height, _, _, _, _, _, _, _, _} = st
  height

def finish(acc: Acc) -> Acc:
  Acc{st, sends, outs} = acc
  St{p, e, h, b, ch, cx, s, l, c, a, _} = st
  Acc{St{p, e, h, b, ch, cx, s, l, c, a, True{}}, sends, outs}

def add_addrs(acc: Acc, +n: U32) -> Acc:
  Acc{st, sends, outs} = acc
  St{p, e, h, b, ch, cx, s, l, c, a, f} = st
  Acc{St{p, e, h, b, ch, cx, s, l, c, (a + n : U32), f}, sends, outs}

# ---- headers -------------------------------------------------------------

def c2_of(c: B.Compact) -> Compact2:
  B.Compact{v, w} = c
  C2{v, w}

def compact2(+xs: +List<U32>) -> Compact2:
  c2_of(B.read_compact(xs))

def c2_value(c: Compact2) -> U32:
  C2{v, _} = c
  v

def c2_width(c: Compact2) -> U32:
  C2{_, w} = c
  w

def c2_sum(c: Compact2) -> U32:
  C2{v, w} = c
  (v + w : U32)

def header_len(+xs: +List<U32>) -> U32:
  (140 + c2_sum(compact2(B.drop(xs, 140n))) : U32)

def tx_count_width(+xs: +List<U32>) -> U32:
  c2_width(compact2(xs))

def parse_one(+xs: +List<U32>) -> (+List<U32> & +List<U32>):
  +len = header_len(xs)
  +raw = B.take_u(xs, len)
  +rest = B.drop_u(xs, len)
  (raw, B.drop_u(rest, tx_count_width(rest)))

def push2(pr: (+List<U32> & +List<U32>), acc: +List<+List<U32>>) -> (+List<U32> & +List<+List<U32>>):
  (raw, rest) = pr
  (rest, raw <> acc)

def push(st: (+List<U32> & +List<+List<U32>>)) -> (+List<U32> & +List<+List<U32>>):
  (xs, acc) = st
  push2(parse_one(xs), acc)

def snd_raws(st: (+List<U32> & +List<+List<U32>>)) -> +List<+List<U32>>:
  (_, acc) = st
  acc

def raws_go(n: Nat, st: (+List<U32> & +List<+List<U32>>)) -> +List<+List<U32>>:
  match n:
    case 0n:
      snd_raws(st)
    case 1n+p:
      raws_go(p, push(st))

def raws_of(+payload: +List<U32>) -> +List<+List<U32>>:
  +c = compact2(payload)
  List.reverse(&2, +List<U32>, raws_go(U32.to_nat(c2_value(c)), (B.drop_u(payload, c2_width(c)), Nil{})))

def header_line(+h: U32, +hash: +List<U32>, +raw: +List<U32>) -> String:
  "  #" ++ u(h) ++ "  " ++ B.hex_rev(hash) ++ "  time " ++ u(B.get_le32(B.drop(raw, 100n)))
    ++ "  bits " ++ B.hex_rev(B.take(B.drop(raw, 104n), 4n)) ++ "  v" ++ u(B.get_le32(raw))
    ++ "  sol " ++ u((B.length(raw) - 143 : U32)) ++ "B"

def show_this(+i: U32, +n: U32) -> Bool:
  Bool.or(U32.is_lt(i, 2), Bool.or(U32.is_eq((i + 1 : U32), n), U32.is_eq((i % 40 : U32), 0)))

def bump_checked(acc: Acc) -> Acc:
  Acc{st, sends, outs} = acc
  St{p, e, h, b, ch, cx, s, l, c, a, f} = st
  Acc{St{p, e, h, b, ch, cx, s, l, (c + 1 : U32), a, f}, sends, outs}

def checkpoint_ok(ok: Bool, acc: Acc, +h: U32) -> Acc:
  match ok:
    case True{}:
      bump_checked(say(acc, "  CHECKPOINT #" ++ u(h) ++ ": SHA-256d computed in Bend == Zebra's mainnet checkpoint"))
    case False{}:
      finish(say(acc, "  CHECKPOINT #" ++ u(h) ++ ": MISMATCH against Zebra's checkpoint"))

def checkpoint_sel(at: Bool, ok: Bool, acc: Acc, +h: U32) -> Acc:
  match at:
    case False{}:
      acc
    case True{}:
      checkpoint_ok(ok, acc, h)

# Checkpoint check: the header at the checkpoint height must hash to Zebra's value.
def checkpoint_say(acc: Acc, +h: U32, +hash: +List<U32>, +ch: U32, +cx: +List<U32>) -> Acc:
  checkpoint_sel(U32.is_eq(h, ch), B.is_eq(hash, cx), acc, h)

def accept(acc: Acc, +raw: +List<U32>, +hash: +List<U32>, +i: U32, +n: U32) -> Acc:
  Acc{st, sends, +outs} = acc
  St{p, _, h0, b, +ch, +cx, s, l, c, a, f} = st
  +h = (h0 + 1 : U32)
  +lines = Bool.pick(+List<String>, show_this(i, n), header_line(h, hash, raw) <> outs, outs)
  +acc2 = {Acc{St{p, hash, h, b, ch, cx, Hdr{h, raw, hash} <> s, (l + 1 : U32), c, a, f}, sends, lines} : Acc}
  checkpoint_say(acc2, h, hash, ch, cx)

def link_sel(ok: Bool, acc: Acc, +raw: +List<U32>, +i: U32, +n: U32) -> Acc:
  match ok:
    case False{}:
      finish(say(acc, "  header " ++ u(i) ++ " does not link to the previous hash: stopping"))
    case True{}:
      accept(acc, raw, H.hash_d(raw), i, n)

# Accept one header if its prev-hash field is the hash we expect next.
def link(+acc: Acc, +raw: +List<U32>, +i: U32, +n: U32) -> Acc:
  link_sel(B.is_eq(B.take(B.drop(raw, 4n), 32n), expect_of(acc)), acc, raw, i, n)

def is_finished(+acc: Acc) -> Bool:
  Acc{st, _, _} = acc
  St{_, _, _, _, _, _, _, _, _, _, f} = st
  f

def link_all(rs: +List<+List<U32>>, +acc: Acc, +i: U32, +n: U32) -> Acc:
  match rs:
    case Nil{}:
      acc
    case Con{r, t}:
      link_all(t, Bool.pick(Acc, is_finished(acc), acc, link(acc, r, i, n)), (i + 1 : U32), n)

def next_sel(stop: Bool, +acc: Acc) -> Acc:
  match stop:
    case True{}:
      finish(acc)
    case False{}:
      send(say(acc, "-> getheaders after #" ++ u(height_of(acc))), "getheaders", M.getheaders_payload(proto_of(acc), expect_of(acc)))

def next_batch(acc: Acc) -> Acc:
  Acc{st, sends, outs} = acc
  St{p, e, h, b, ch, cx, s, l, c, a, f} = st
  +left = (b - 1 : U32)
  next_sel(Bool.or(f, U32.is_eq(left, 0)), Acc{St{p, e, h, left, ch, cx, s, l, c, a, f}, sends, outs})

def on_headers(+payload: +List<U32>, acc: Acc) -> Acc:
  +rs = raws_of(payload)
  +n = U32.from_nat(List.length(&2, +List<U32>, rs))
  next_batch(link_all(rs, say(acc, "<- headers: " ++ u(n) ++ " headers, " ++ u(B.length(payload)) ++ " bytes"), 0, n))

# ---- other messages -------------------------------------------------------

def on_version(+payload: +List<U32>, acc: Acc) -> Acc:
  +ua_at = B.drop(payload, 80n)
  +c = compact2(ua_at)
  +ua_len = c2_value(c)
  +ua_w = c2_width(c)
  +ua = B.to_string(B.take_u(B.drop_u(ua_at, ua_w), ua_len))
  +best = B.get_le32(B.drop_u(ua_at, (ua_w + ua_len : U32)))
  send(say(acc, "<- version: protocol " ++ u(B.get_le32(payload)) ++ ", user agent " ++ ua
    ++ ", best height " ++ u(best) ++ "\n-> verack"), "verack", Nil{})

def on_verack(+acc: Acc) -> Acc:
  +a2 = say(acc, "<- verack: handshake complete\n-> getheaders after #" ++ u(height_of(acc))
    ++ " (" ++ B.hex_rev(expect_of(acc)) ++ ")\n-> getaddr")
  send(send(a2, "getheaders", M.getheaders_payload(proto_of(a2), expect_of(a2))), "getaddr", Nil{})

def on_ping(+payload: +List<U32>, acc: Acc) -> Acc:
  send(say(acc, "<- ping " ++ B.hex(payload) ++ "  -> pong"), "pong", payload)

def on_addr(+payload: +List<U32>, acc: Acc) -> Acc:
  +n = c2_value(compact2(payload))
  add_addrs(say(acc, "<- addr: " ++ u(n) ++ " peer addresses"), n)

def on_other(+cmd: String, +payload: +List<U32>, acc: Acc) -> Acc:
  say(acc, "<- " ++ cmd ++ " (" ++ u(B.length(payload)) ++ " bytes)")

def is_cmd(+cmd: String, lit: String) -> Bool:
  String.eq(cmd, lit)

def dispatch6(+cmd: String, +payload: +List<U32>, acc: Acc, b: Bool) -> Acc:
  match b:
    case True{}:
      on_addr(payload, acc)
    case False{}:
      on_other(cmd, payload, acc)

def dispatch5(+cmd: String, +payload: +List<U32>, acc: Acc, a: Bool, b: Bool) -> Acc:
  match a:
    case True{}:
      on_addr(payload, acc)
    case False{}:
      dispatch6(cmd, payload, acc, b)

def dispatch4(+cmd: String, +payload: +List<U32>, acc: Acc, h: Bool) -> Acc:
  match h:
    case True{}:
      on_headers(payload, acc)
    case False{}:
      dispatch5(cmd, payload, acc, is_cmd(cmd, "addr"), is_cmd(cmd, "addrv2"))

def dispatch3(+cmd: String, +payload: +List<U32>, acc: Acc, p: Bool) -> Acc:
  match p:
    case True{}:
      on_ping(payload, acc)
    case False{}:
      dispatch4(cmd, payload, acc, is_cmd(cmd, "headers"))

def dispatch2(+cmd: String, +payload: +List<U32>, acc: Acc, va: Bool) -> Acc:
  match va:
    case True{}:
      on_verack(acc)
    case False{}:
      dispatch3(cmd, payload, acc, is_cmd(cmd, "ping"))

def dispatch1(+cmd: String, +payload: +List<U32>, acc: Acc, v: Bool) -> Acc:
  match v:
    case True{}:
      on_version(payload, acc)
    case False{}:
      dispatch2(cmd, payload, acc, is_cmd(cmd, "verack"))

def handle(m: M.Msg, acc: Acc) -> Acc:
  M.Msg{+cmd, +payload} = m
  dispatch1(cmd, payload, acc, is_cmd(cmd, "version"))

def drain_stop(pr: M.Parsed, acc: Acc) -> Drained:
  match pr:
    case M.NeedMore{buf}:
      Drained{buf, acc}
    case M.Got{m, rest}:
      Drained{rest, acc}
    case M.Bad{why}:
      Drained{Nil{}, finish(say(acc, "!! " ++ why))}

def drain(n: Nat, pr: M.Parsed, acc: Acc) -> Drained:
  match n:
    case 0n:
      drain_stop(pr, acc)
    case 1n+p:
      match pr:
        case M.NeedMore{buf}:
          Drained{buf, acc}
        case M.Got{m, rest}:
          drain(p, M.parse(rest), handle(m, acc))
        case M.Bad{why}:
          Drained{Nil{}, finish(say(acc, "!! " ++ why))}
