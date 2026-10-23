//! Oracle for node/headers: fetches raw mainnet headers and checks them with Rust.
use anyhow::{anyhow, Result};
use tonic::transport::{Channel, ClientTlsConfig};

const SERVICE: &str = "/cash.z.wallet.sdk.rpc.CompactTxStreamer";

#[derive(Clone, PartialEq, prost::Message)]
pub struct BlockId { #[prost(uint64, tag = "1")] pub height: u64, #[prost(bytes = "vec", tag = "2")] pub hash: Vec<u8> }
#[derive(Clone, PartialEq, prost::Message)]
pub struct BlockRange { #[prost(message, optional, tag = "1")] pub start: Option<BlockId>, #[prost(message, optional, tag = "2")] pub end: Option<BlockId>, #[prost(int32, repeated, tag = "3")] pub pool_types: Vec<i32> }
#[derive(Clone, PartialEq, prost::Message)]
pub struct CompactBlock {
    #[prost(uint64, tag = "2")] pub height: u64,
    #[prost(bytes = "vec", tag = "3")] pub hash: Vec<u8>,
    #[prost(bytes = "vec", tag = "4")] pub prev_hash: Vec<u8>,
    #[prost(uint32, tag = "5")] pub time: u32,
    #[prost(bytes = "vec", tag = "6")] pub header: Vec<u8>,
}

async fn connect(url: &str) -> Result<tonic::client::Grpc<Channel>> {
    let _ = rustls::crypto::ring::default_provider().install_default();
    let ch = Channel::from_shared(url.to_string())?.tls_config(ClientTlsConfig::new().with_webpki_roots())?.connect().await?;
    Ok(tonic::client::Grpc::new(ch))
}

#[tokio::main]
async fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("probe") => {
            let mut g = connect("https://zec.rocks:443").await?;
            g.ready().await?;
            let h: u64 = args[2].parse()?;
            let req = BlockRange { start: Some(BlockId { height: h, hash: vec![] }), end: Some(BlockId { height: h + 2, hash: vec![] }), pool_types: vec![] };
            let mut s = g.server_streaming::<_, CompactBlock, _>(tonic::Request::new(req), format!("{SERVICE}/GetBlockRange").parse()?, tonic_prost::ProstCodec::default()).await?.into_inner();
            while let Some(b) = s.message().await? {
                println!("height {} hash {} header_len {} time {}", b.height, hex::encode(&b.hash), b.header.len(), b.time);
            }
            Ok(())
        }
        Some("fetch") => fetch(args[2].parse()?, args[3].parse()?, &args[4]).await,
        Some("check") => check(&args[2], args[3].parse()?),
        Some("lines") => lines(&args[2], args[3].parse()?),
        Some("tamper") => tamper(&args[2], &args[3]),
        _ => Err(anyhow!("usage: probe HEIGHT | fetch START COUNT OUT.bin | check FILE START")),
    }
}

// ---- P2P ------------------------------------------------------------------

use sha2::{Digest, Sha256};
use std::time::Instant;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

const MAGIC: [u8; 4] = [0x24, 0xe9, 0x27, 0x64];
pub const HEADER_LEN: usize = 1487;

pub fn sha256d(b: &[u8]) -> [u8; 32] {
    Sha256::digest(Sha256::digest(b)).into()
}

fn varint(v: u64, out: &mut Vec<u8>) {
    match v {
        0..=0xfc => out.push(v as u8),
        0xfd..=0xffff => { out.push(0xfd); out.extend_from_slice(&(v as u16).to_le_bytes()); }
        0x10000..=0xffff_ffff => { out.push(0xfe); out.extend_from_slice(&(v as u32).to_le_bytes()); }
        _ => { out.push(0xff); out.extend_from_slice(&v.to_le_bytes()); }
    }
}

fn read_varint(b: &[u8], i: &mut usize) -> Result<u64> {
    let t = *b.get(*i).ok_or_else(|| anyhow!("eof"))?;
    *i += 1;
    let (n, v) = match t {
        0xfd => (2, u16::from_le_bytes(b[*i..*i + 2].try_into()?) as u64),
        0xfe => (4, u32::from_le_bytes(b[*i..*i + 4].try_into()?) as u64),
        0xff => (8, u64::from_le_bytes(b[*i..*i + 8].try_into()?)),
        x => (0, x as u64),
    };
    *i += n;
    Ok(v)
}

async fn send(s: &mut TcpStream, cmd: &str, payload: &[u8]) -> Result<()> {
    let mut m = Vec::with_capacity(24 + payload.len());
    m.extend_from_slice(&MAGIC);
    let mut c = [0u8; 12];
    c[..cmd.len()].copy_from_slice(cmd.as_bytes());
    m.extend_from_slice(&c);
    m.extend_from_slice(&(payload.len() as u32).to_le_bytes());
    m.extend_from_slice(&sha256d(payload)[..4]);
    m.extend_from_slice(payload);
    s.write_all(&m).await?;
    Ok(())
}

async fn recv(s: &mut TcpStream) -> Result<(String, Vec<u8>)> {
    let mut h = [0u8; 24];
    s.read_exact(&mut h).await?;
    if h[..4] != MAGIC {
        return Err(anyhow!("bad magic"));
    }
    let cmd = String::from_utf8_lossy(&h[4..16]).trim_end_matches('\0').to_string();
    let len = u32::from_le_bytes(h[16..20].try_into()?) as usize;
    let mut p = vec![0u8; len];
    s.read_exact(&mut p).await?;
    if sha256d(&p)[..4] != h[20..24] {
        return Err(anyhow!("bad checksum on {cmd}"));
    }
    Ok((cmd, p))
}

fn version_payload(proto: i32, start_height: i32) -> Vec<u8> {
    let mut v = Vec::new();
    v.extend_from_slice(&proto.to_le_bytes());
    v.extend_from_slice(&1u64.to_le_bytes()); // NODE_NETWORK
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() as i64;
    v.extend_from_slice(&now.to_le_bytes());
    for _ in 0..2 {
        v.extend_from_slice(&1u64.to_le_bytes());
        let mut ip = [0u8; 16];
        ip[10] = 0xff;
        ip[11] = 0xff;
        v.extend_from_slice(&ip);
        v.extend_from_slice(&8233u16.to_be_bytes());
    }
    v.extend_from_slice(&0x5a65_6265_6e64u64.to_le_bytes()); // nonce
    let ua = b"/Zebend-headers:0.1/";
    varint(ua.len() as u64, &mut v);
    v.extend_from_slice(ua);
    v.extend_from_slice(&start_height.to_le_bytes());
    v.push(0);
    v
}

fn proto() -> i32 {
    std::env::var("PROTO").ok().and_then(|v| v.parse().ok()).unwrap_or(170_140)
}

async fn handshake(addr: std::net::SocketAddr) -> Result<(TcpStream, i32, String)> {
    let mut s = tokio::time::timeout(std::time::Duration::from_secs(6), TcpStream::connect(addr)).await??;
    send(&mut s, "version", &version_payload(proto(), 3_530_000)).await?;
    let (mut their_ver, mut ua, mut got_verack, mut got_version) = (0, String::new(), false, false);
    while !(got_verack && got_version) {
        let (cmd, p) = tokio::time::timeout(std::time::Duration::from_secs(10), recv(&mut s)).await??;
        match cmd.as_str() {
            "version" => {
                their_ver = i32::from_le_bytes(p[..4].try_into()?);
                let mut i = 80;
                let l = read_varint(&p, &mut i)? as usize;
                ua = String::from_utf8_lossy(&p[i..i + l]).to_string();
                got_version = true;
                send(&mut s, "verack", &[]).await?;
            }
            "verack" => got_verack = true,
            "reject" => return Err(anyhow!("rejected: {}", String::from_utf8_lossy(&p))),
            _ => {}
        }
    }
    Ok((s, their_ver, ua))
}

async fn block_hash_at(height: u64) -> Result<[u8; 32]> {
    let mut g = connect("https://zec.rocks:443").await?;
    g.ready().await?;
    let b: CompactBlock = g
        .unary(tonic::Request::new(BlockId { height, hash: vec![] }), format!("{SERVICE}/GetBlock").parse()?, tonic_prost::ProstCodec::default())
        .await?
        .into_inner();
    b.hash.as_slice().try_into().map_err(|_| anyhow!("bad hash"))
}

/// Fetches COUNT headers starting at height START from mainnet peers into OUT
/// (raw 1487-byte records), and writes OUT.hashes with lightwalletd's hash for
/// every 1000th height (plus first and last) for cross-checking.
async fn fetch(start: u64, count: usize, out: &str) -> Result<()> {
    let mut locator = block_hash_at(start - 1).await?;
    let mut peers: Vec<std::net::SocketAddr> = Vec::new();
    for seed in ["mainnet.seeder.zfnd.org:8233", "dnsseed.z.cash:8233", "dnsseed.str4d.xyz:8233", "mainnet.is.yolo.money:8233", "mainnet.seeder.shieldedinfra.net:8233"] {
        if let Ok(it) = tokio::net::lookup_host(seed).await {
            peers.extend(it.filter(|a| a.is_ipv4()));
        }
    }
    let mut headers: Vec<u8> = Vec::with_capacity(count * HEADER_LEN);
    let t = Instant::now();
    'peers: for addr in peers {
        let (mut s, ver, ua) = match handshake(addr).await { Ok(x) => x, Err(e) => { eprintln!("handshake {addr}: {e}"); continue } };
        eprintln!("connected {addr} proto {ver} {ua}");
        while headers.len() / HEADER_LEN < count {
            let mut gh = Vec::new();
            gh.extend_from_slice(&proto().to_le_bytes());
            varint(1, &mut gh);
            gh.extend_from_slice(&locator);
            gh.extend_from_slice(&[0u8; 32]);
            if send(&mut s, "getheaders", &gh).await.is_err() {
                continue 'peers;
            }
            let p = loop {
                let r = tokio::time::timeout(std::time::Duration::from_secs(20), recv(&mut s)).await;
                let Ok(Ok((cmd, p))) = r else { continue 'peers };
                match cmd.as_str() {
                    "headers" => break p,
                    "ping" => { let _ = send(&mut s, "pong", &p).await; }
                    _ => {}
                }
            };
            let mut i = 0;
            let n = read_varint(&p, &mut i)? as usize;
            if n == 0 {
                eprintln!("peer {addr} returned 0 headers after {}: at its tip", hex::encode(locator));
                break 'peers;
            }
            for _ in 0..n {
                let h = &p[i..i + HEADER_LEN];
                if h[140..143] != [0xfd, 0x40, 0x05] {
                    return Err(anyhow!("unexpected solution length prefix"));
                }
                if h[4..36] != locator {
                    eprintln!("peer {addr} sent a non-linking header (n={n}): prev {} want {} self {}; switching peer", hex::encode(&h[4..36]), hex::encode(locator), hex::encode(sha256d(h)));
                    continue 'peers;
                }
                locator = sha256d(h);
                headers.extend_from_slice(h);
                i += HEADER_LEN;
                read_varint(&p, &mut i)?; // tx count (0)
                if headers.len() / HEADER_LEN == count {
                    break;
                }
            }
            let got = headers.len() / HEADER_LEN;
            if got % 8000 < 160 {
                eprintln!("  {got} headers ({:.0}/s)", got as f64 / t.elapsed().as_secs_f64());
            }
        }
        break;
    }
    let got = headers.len() / HEADER_LEN;
    std::fs::write(out, &headers)?;
    let mut checks = String::new();
    for k in (0..got).filter(|k| k % 1000 == 0 || *k == got - 1) {
        let h = start + k as u64;
        checks += &format!("{h} {}\n", hex::encode(block_hash_at(h).await?));
    }
    std::fs::write(format!("{out}.hashes"), checks)?;
    println!("fetched {got} headers [{start}, {}] in {:?}", start + got as u64 - 1, t.elapsed());
    Ok(())
}

// ---- Reference checks ------------------------------------------------------

/// Expands a compact nBits into a 256-bit big-endian target (None if negative/overflow).
pub fn target_be(bits: u32) -> Option<[u8; 32]> {
    let exp = (bits >> 24) as usize;
    let mant = bits & 0x007f_ffff;
    if bits & 0x0080_0000 != 0 || exp > 32 {
        return None;
    }
    let mut t = [0u8; 32];
    let m = mant.to_be_bytes(); // [0, b2, b1, b0]
    for (j, byte) in m[1..].iter().enumerate() {
        let pos = 32 - exp + j as isize as usize;
        if exp >= 3 - j && pos < 32 {
            t[pos] = *byte;
        } else if *byte != 0 && exp < 3 - j {
            // bytes shifted out below the units place are dropped
        }
    }
    if exp < 3 {
        let v = mant >> (8 * (3 - exp));
        t = [0u8; 32];
        t[28..].copy_from_slice(&v.to_be_bytes());
    }
    Some(t)
}

fn check(file: &str, start: u64) -> Result<()> {
    use rayon::prelude::*;
    let b = std::fs::read(file)?;
    let n = b.len() / HEADER_LEN;
    let hs: Vec<&[u8]> = b.chunks_exact(HEADER_LEN).collect();
    let hashes: Vec<[u8; 32]> = hs.iter().map(|h| sha256d(h)).collect();
    let mut link_ok = 0;
    for i in 1..n {
        link_ok += (hs[i][4..36] == hashes[i - 1]) as usize;
    }
    let mut target_ok = 0;
    for (h, hash) in hs.iter().zip(&hashes) {
        let bits = u32::from_le_bytes(h[104..108].try_into()?);
        let t = target_be(bits).ok_or_else(|| anyhow!("bad bits"))?;
        let mut be = *hash;
        be.reverse();
        target_ok += (be <= t) as usize;
    }
    let lwd = std::fs::read_to_string(format!("{file}.hashes")).unwrap_or_default();
    let (mut lwd_ok, mut lwd_n) = (0, 0);
    for line in lwd.lines() {
        let mut it = line.split(' ');
        let (h, x): (u64, &str) = (it.next().unwrap().parse()?, it.next().unwrap());
        lwd_n += 1;
        lwd_ok += (hex::encode(hashes[(h - start) as usize]) == x) as usize;
    }
    let eq = |h: &[u8]| equihash::is_valid_solution(200, 9, &h[..108], &h[108..140], &h[143..]).is_ok();
    let t = Instant::now();
    let m = n.min(2000);
    let single = hs.iter().take(m).filter(|h| eq(h)).count();
    let dt1 = t.elapsed();
    let t = Instant::now();
    let eq_ok = hs.par_iter().filter(|h| eq(h)).count();
    let dtn = t.elapsed();
    println!("headers {n} [{start}, {}]", start + n as u64 - 1);
    println!("prev-hash links {link_ok}/{}", n - 1);
    println!("hash <= target {target_ok}/{n}");
    println!("lightwalletd hash spot checks {lwd_ok}/{lwd_n}");
    println!("equihash valid (rust, {} threads) {eq_ok}/{n} in {dtn:?} = {:.0} headers/s", rayon::current_num_threads(), n as f64 / dtn.as_secs_f64());
    println!("equihash rust 1 thread: {m} headers ({single} valid) in {dt1:?} = {:.0} headers/s", m as f64 / dt1.as_secs_f64());
    Ok(())
}

/// Same format as t/pow_test.bend: index, block hash hex, Equihash validity, hash <= target.
fn lines(file: &str, n: usize) -> Result<()> {
    let b = std::fs::read(file)?;
    for (i, h) in b.chunks_exact(HEADER_LEN).take(n).enumerate() {
        let hash = sha256d(h);
        let pow = equihash::is_valid_solution(200, 9, &h[..108], &h[108..140], &h[143..]).is_ok();
        let bits = u32::from_le_bytes(h[104..108].try_into()?);
        let mut be = hash;
        be.reverse();
        let under = be <= target_be(bits).ok_or_else(|| anyhow!("bits"))?;
        println!("{i} {} pow {} target {}", hex::encode(hash), pow as u8, under as u8);
    }
    Ok(())
}

/// Writes adversarial variants of the first header: flipped solution bits at several
/// positions, swapped index halves, a duplicated index, a changed nonce, raised nBits difficulty.
fn tamper(file: &str, out: &str) -> Result<()> {
    let b = std::fs::read(file)?;
    let h0 = &b[..HEADER_LEN];
    let mut v: Vec<Vec<u8>> = vec![h0.to_vec()];
    for pos in [143usize, 144, 500, 1000, 1486] {
        let mut h = h0.to_vec();
        h[pos] ^= 0x01;
        v.push(h);
    }
    // swap the two halves of the solution (breaks index ordering, keeps the XOR)
    let mut h = h0.to_vec();
    let (a, c) = (h[143..815].to_vec(), h[815..].to_vec());
    h[143..815].copy_from_slice(&c);
    h[815..].copy_from_slice(&a);
    v.push(h);
    // nonce change
    let mut h = h0.to_vec();
    h[120] ^= 0x80;
    v.push(h);
    // header field change (time)
    let mut h = h0.to_vec();
    h[100] ^= 0x01;
    v.push(h);
    // harder nBits: shrink the exponent so the hash no longer meets the target
    let mut h = h0.to_vec();
    h[107] -= 3;
    v.push(h);
    std::fs::write(out, v.concat())?;
    println!("wrote {} variants", v.len());
    Ok(())
}
