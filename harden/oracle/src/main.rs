//! Differential fuzzing oracle for Zebend's Bend parsers.
//!
//!   harden-oracle cs     N OUT   CompactSize            (zcash_encoding::CompactSize::read)
//!   harden-oracle hdr    N OUT   block header           (zcash_primitives BlockHeader::read)
//!   harden-oracle frame  N OUT   P2P message framing    (reference rules, see `frame_verdict`)
//!   harden-oracle tx     N OUT   transaction v1..v6     (zcash_primitives Transaction::read)
//!   harden-oracle block  N OUT   full block             (header + CompactSize + Transaction::read)
//!
//! Writes OUT.cases (u32 LE length + bytes per case), OUT.expect (one verdict line per case) and
//! OUT.kinds (the mutation that produced each case). Paths are relative to bend-zcash/.

use std::{
    fs,
    io::{Cursor, Write},
};

use anyhow::{bail, Result};
use sha2::{Digest, Sha256};
use zcash_encoding::CompactSize;
use zcash_primitives::{block::BlockHeader, transaction::Transaction};
use zcash_protocol::consensus::{BlockHeight, BranchId, MainNetwork};

const ROOT: &str = "../..";
const HEADER_LEN: usize = 1487;
const MAX_FRAME_PAYLOAD: u32 = 2 * 1024 * 1024;
const MAGIC: [u8; 4] = [0x24, 0xe9, 0x27, 0x64];

struct Rng(u64);
impl Rng {
    /// A per-generator seed, varied by HARDEN_SEED to produce further independent batches.
    fn seeded(base: u64) -> Rng {
        let extra: u64 = std::env::var("HARDEN_SEED").ok().and_then(|s| s.parse().ok()).unwrap_or(0);
        Rng(base ^ extra.wrapping_mul(0xd1b54a32d192ed03))
    }
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e3779b97f4a7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
        z ^ (z >> 31)
    }
    fn below(&mut self, n: usize) -> usize {
        if n == 0 { 0 } else { (self.next() % n as u64) as usize }
    }
    fn byte(&mut self) -> u8 {
        self.next() as u8
    }
    fn bytes(&mut self, n: usize) -> Vec<u8> {
        (0..n).map(|_| self.byte()).collect()
    }
}

struct Out {
    cases: Vec<u8>,
    expect: String,
    kinds: String,
    n: usize,
}

impl Out {
    fn new() -> Self {
        Out { cases: Vec::new(), expect: String::new(), kinds: String::new(), n: 0 }
    }
    fn push(&mut self, kind: &str, bytes: &[u8], verdict: String) {
        self.cases.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
        self.cases.extend_from_slice(bytes);
        self.expect.push_str(&verdict);
        self.expect.push('\n');
        self.kinds.push_str(kind);
        self.kinds.push('\n');
        self.n += 1;
    }
    fn save(&self, out: &str) -> Result<()> {
        fs::write(format!("{out}.cases"), &self.cases)?;
        fs::write(format!("{out}.expect"), &self.expect)?;
        fs::write(format!("{out}.kinds"), &self.kinds)?;
        let acc = self.expect.lines().filter(|l| !l.starts_with('0')).count();
        eprintln!("{out}: {} cases ({} accepted by the oracle), {} bytes", self.n, acc, self.cases.len());
        Ok(())
    }
}

// ---------------------------------------------------------------- generic mutations

fn mutate(rng: &mut Rng, seed: &[u8], others: &[Vec<u8>]) -> (String, Vec<u8>) {
    let mut b = seed.to_vec();
    let len = b.len();
    let k = rng.below(13);
    let kind = match k {
        0 => "keep",
        1 => {
            b.truncate(rng.below(len.max(1)));
            "truncate"
        }
        2 => {
            let extra = 1 + rng.below(24);
            b.extend(rng.bytes(extra));
            "append"
        }
        3 => {
            for _ in 0..1 + rng.below(4) {
                if !b.is_empty() {
                    let i = rng.below(b.len());
                    b[i] ^= 1 << rng.below(8);
                }
            }
            "bitflip"
        }
        4 => {
            for _ in 0..1 + rng.below(3) {
                if !b.is_empty() {
                    let i = rng.below(b.len().min(96));
                    b[i] = rng.byte();
                }
            }
            "head_byte"
        }
        5 => {
            if !b.is_empty() {
                let i = rng.below(b.len());
                b[i] = [0x00, 0x01, 0xfc, 0xfd, 0xfe, 0xff][rng.below(6)];
            }
            "size_marker"
        }
        6 => {
            if b.len() >= 4 {
                let i = rng.below(b.len() - 3);
                let w = rng.bytes(4);
                b[i..i + 4].copy_from_slice(&w);
            }
            "word"
        }
        7 => {
            let o = &others[rng.below(others.len())];
            if !o.is_empty() && !b.is_empty() {
                let i = rng.below(b.len());
                let j = rng.below(o.len());
                let n = rng.below((o.len() - j).min(512) + 1);
                b.truncate(i);
                b.extend_from_slice(&o[j..j + n]);
            }
            "splice"
        }
        8 => {
            if !b.is_empty() {
                let i = rng.below(b.len());
                b.remove(i);
            }
            "delete_byte"
        }
        9 => {
            let i = rng.below(b.len() + 1);
            b.insert(i, rng.byte());
            "insert_byte"
        }
        10 => {
            // Rewrite one 32-byte aligned-ish window: hits point / field encodings.
            if b.len() >= 32 {
                let i = rng.below(b.len() - 31);
                let mode = rng.below(3);
                for (t, x) in b[i..i + 32].iter_mut().enumerate() {
                    *x = match mode {
                        0 => 0,
                        1 => 0xff,
                        _ => if t == 31 { rng.byte() | 0x40 } else { rng.byte() },
                    };
                }
            }
            "field32"
        }
        11 => {
            let n = rng.below(2048);
            b = rng.bytes(n);
            if b.len() >= 8 && rng.below(2) == 0 {
                b[..4].copy_from_slice(&seed[..4.min(seed.len())].iter().copied().chain([0; 4]).take(4).collect::<Vec<_>>());
            }
            "garbage"
        }
        _ => {
            b.extend_from_slice(&others[rng.below(others.len())]);
            "concat"
        }
    };
    (kind.to_string(), b)
}

// ---------------------------------------------------------------- CompactSize

fn cs_verdict(b: &[u8]) -> String {
    let mut c = Cursor::new(b);
    match CompactSize::read(&mut c) {
        Ok(v) => format!("1 {} {}", v, c.position()),
        Err(_) => "0".into(),
    }
}

fn gen_cs(n: usize, out: &str) -> Result<()> {
    let mut rng = Rng::seeded(0xc5);
    let mut o = Out::new();
    let interesting: [u64; 14] = [
        0, 1, 252, 253, 254, 255, 0xffff, 0x10000, 0xffff_ffff, 0x0200_0000, 0x0200_0001, 0x1_0000_0000,
        u64::MAX, 0x1234_5678_9abc,
    ];
    for i in 0..n {
        let mut b = Vec::new();
        let kind;
        match i % 4 {
            0 => {
                kind = "random";
                b = { let k = rng.below(11); rng.bytes(k) };
            }
            1 => {
                kind = "marker";
                b.push([253u8, 254, 255][rng.below(3)]);
                b.extend({ let k = rng.below(10); rng.bytes(k) });
            }
            2 => {
                // Canonical and non-canonical encodings of interesting values, at every width.
                kind = "value";
                let v = interesting[rng.below(interesting.len())].wrapping_add(rng.below(3) as u64).wrapping_sub(1);
                match rng.below(4) {
                    0 => b.push(v as u8),
                    1 => {
                        b.push(253);
                        b.extend((v as u16).to_le_bytes());
                    }
                    2 => {
                        b.push(254);
                        b.extend((v as u32).to_le_bytes());
                    }
                    _ => {
                        b.push(255);
                        b.extend(v.to_le_bytes());
                    }
                }
                b.extend({ let k = rng.below(3); rng.bytes(k) });
            }
            _ => {
                kind = "truncated";
                b.push([253u8, 254, 255][rng.below(3)]);
                b.extend({ let k = rng.below(8); rng.bytes(k) });
                let keep = rng.below(b.len() + 1);
                b.truncate(keep);
            }
        }
        o.push(kind, &b, cs_verdict(&b));
    }
    o.save(out)
}

// ---------------------------------------------------------------- headers

/// Zebend accepts a header iff the official parser reads it in full AND its Equihash
/// solution has the (200,9) length of 1344 bytes (as Zebra requires).
fn hdr_verdict(b: &[u8]) -> String {
    let mut c = Cursor::new(b);
    match BlockHeader::read(&mut c) {
        Ok(h) if c.position() as usize == b.len() && h.solution.len() == 1344 => "1".into(),
        _ => "0".into(),
    }
}

fn load_headers(count: usize) -> Result<Vec<Vec<u8>>> {
    let raw = fs::read(format!("{ROOT}/node/headers/data/mainnet.bin"))?;
    Ok(raw.chunks_exact(HEADER_LEN).take(count).map(|c| c.to_vec()).collect())
}

fn gen_hdr(n: usize, out: &str) -> Result<()> {
    let seeds = load_headers(4000)?;
    let mut rng = Rng::seeded(0x4d);
    let mut o = Out::new();
    for _ in 0..n {
        let s = &seeds[rng.below(seeds.len())];
        let (kind, b) = if rng.below(6) == 0 {
            // Solution length prefix rewritten (canonical / non-canonical / other lengths).
            let mut b = s.clone();
            let len = [1344u32, 1343, 1345, 0, 252, 253, 400][rng.below(7)];
            let mut prefix = Vec::new();
            if rng.below(3) == 0 {
                prefix.push(254);
                prefix.extend(len.to_le_bytes());
            } else if len < 253 {
                prefix.push(len as u8);
            } else {
                prefix.push(253);
                prefix.extend((len as u16).to_le_bytes());
            }
            let sol: Vec<u8> = b[143..].to_vec();
            b.truncate(140);
            b.extend(prefix);
            b.extend(sol.iter().copied().chain(std::iter::repeat(0)).take(len as usize));
            ("sol_len".to_string(), b)
        } else {
            mutate(&mut rng, s, &seeds)
        };
        let v = hdr_verdict(&b);
        o.push(&kind, &b, v);
    }
    o.save(out)
}

// ---------------------------------------------------------------- P2P framing

fn sha256d4(p: &[u8]) -> [u8; 4] {
    let h = Sha256::digest(Sha256::digest(p));
    [h[0], h[1], h[2], h[3]]
}

/// Reference rules (zcashd CMessageHeader::IsValid + IsCommandValid, MAX_PROTOCOL_MESSAGE_LENGTH):
///   "0"  invalid: bad magic, bad command (printable ASCII up to the first NUL, then only NULs),
///        payload length > 2 MiB (rejected from the header alone), or checksum mismatch;
///   "2"  need more bytes (fewer than 24, or the declared payload is not all here yet);
///   "1 <cmd> <len>"  one complete valid message.
fn frame_verdict(b: &[u8]) -> String {
    if b.len() < 24 {
        return "2".into();
    }
    if b[..4] != MAGIC {
        return "0".into();
    }
    let cmd = &b[4..16];
    let mut seen_nul = false;
    for &c in cmd {
        if c == 0 {
            seen_nul = true;
        } else if seen_nul || !(0x20..=0x7e).contains(&c) {
            return "0".into();
        }
    }
    let len = u32::from_le_bytes(b[16..20].try_into().unwrap());
    if len > MAX_FRAME_PAYLOAD {
        return "0".into();
    }
    if b.len() < 24 + len as usize {
        return "2".into();
    }
    let payload = &b[24..24 + len as usize];
    if sha256d4(payload) != b[20..24] {
        return "0".into();
    }
    let name: String = cmd.iter().take_while(|&&c| c != 0).map(|&c| c as char).collect();
    format!("1 {} {}", if name.is_empty() { "-".into() } else { name }, len)
}

fn frame(cmd: &str, payload: &[u8]) -> Vec<u8> {
    let mut f = MAGIC.to_vec();
    let mut c = [0u8; 12];
    c[..cmd.len()].copy_from_slice(cmd.as_bytes());
    f.extend(c);
    f.extend((payload.len() as u32).to_le_bytes());
    f.extend(sha256d4(payload));
    f.extend(payload);
    f
}

fn gen_frame(n: usize, out: &str) -> Result<()> {
    let hdrs = load_headers(40)?;
    let mut seeds = vec![
        frame("verack", &[]),
        frame("ping", &[1, 2, 3, 4, 5, 6, 7, 8]),
        frame("getaddr", &[]),
        frame("version", &[0x6e; 102]),
    ];
    let mut hs = vec![2u8];
    hs.extend(&hdrs[0]);
    hs.push(0);
    hs.extend(&hdrs[1]);
    hs.push(0);
    seeds.push(frame("headers", &hs));
    let mut rng = Rng::seeded(0xf7);
    let mut o = Out::new();
    for _ in 0..n {
        let s = &seeds[rng.below(seeds.len())];
        let (kind, b) = match rng.below(8) {
            0 => {
                // Oversized declared length, payload absent: must be rejected without waiting.
                let mut b = s[..20].to_vec();
                let len = [MAX_FRAME_PAYLOAD, MAX_FRAME_PAYLOAD + 1, u32::MAX, 0x8000_0000][rng.below(4)];
                b[16..20].copy_from_slice(&len.to_le_bytes());
                b.extend(&s[20..24]);
                b.extend({ let k = rng.below(64); rng.bytes(k) });
                ("big_len".to_string(), b)
            }
            1 => {
                let mut b = s.clone();
                for i in 0..12 {
                    b[4 + i] = match rng.below(5) {
                        0 => 0,
                        1 => rng.byte(),
                        2 => 0x7f,
                        _ => b[4 + i],
                    };
                }
                let p = b[24..].to_vec();
                let ck = sha256d4(&p);
                b[20..24].copy_from_slice(&ck);
                ("command".to_string(), b)
            }
            _ => mutate(&mut rng, s, &seeds),
        };
        let v = frame_verdict(&b);
        o.push(&kind, &b, v);
    }
    o.save(out)
}

// ---------------------------------------------------------------- transactions & blocks

fn tx_verdict(b: &[u8], branch: BranchId) -> String {
    let mut c = Cursor::new(b);
    match Transaction::read(&mut c, branch) {
        Ok(_) if c.position() as usize == b.len() => "1".into(),
        _ => "0".into(),
    }
}

struct BlockSeed {
    height: u32,
    bytes: Vec<u8>,
    txs: Vec<Vec<u8>>,
}

fn load_blocks() -> Result<Vec<BlockSeed>> {
    let mut out = Vec::new();
    let dir = format!("{ROOT}/node/block/data");
    let mut names: Vec<_> = fs::read_dir(&dir)?.filter_map(|e| e.ok()).map(|e| e.file_name().into_string().unwrap()).filter(|n| n.ends_with(".bin")).collect();
    names.sort();
    for name in names {
        let height: u32 = name.trim_end_matches(".bin").parse()?;
        let bytes = fs::read(format!("{dir}/{name}"))?;
        let branch = BranchId::for_height(&MainNetwork, BlockHeight::from_u32(height));
        let mut c = Cursor::new(&bytes[..]);
        BlockHeader::read(&mut c)?;
        let count = CompactSize::read(&mut c)?;
        let mut txs = Vec::new();
        for _ in 0..count {
            let start = c.position() as usize;
            Transaction::read(&mut c, branch)?;
            txs.push(bytes[start..c.position() as usize].to_vec());
        }
        if c.position() as usize != bytes.len() {
            bail!("trailing bytes in block {height}");
        }
        out.push(BlockSeed { height, bytes, txs });
    }
    Ok(out)
}

fn load_tx_seeds() -> Result<Vec<(Vec<u8>, BranchId)>> {
    let mut seeds = Vec::new();
    let dir = format!("{ROOT}/node/tx/mainnet");
    let index = fs::read_to_string(format!("{dir}/index.txt"))?;
    for line in index.lines() {
        let f: Vec<&str> = line.split_whitespace().collect();
        let height: u32 = f[2].parse()?;
        let bytes = fs::read(format!("{dir}/{}.bin", f[0]))?;
        seeds.push((bytes, BranchId::for_height(&MainNetwork, BlockHeight::from_u32(height))));
    }
    for b in load_blocks()? {
        let branch = BranchId::for_height(&MainNetwork, BlockHeight::from_u32(b.height));
        for t in b.txs {
            seeds.push((t, branch));
        }
    }
    seeds.extend(synthetic_seeds());
    Ok(seeds)
}

/// Pre-Sapling shapes absent from the mainnet sample: Sprout v1, v2 with a PHGR joinsplit,
/// Overwinter v3 with a joinsplit, and v4 with a Groth16 joinsplit and no Sapling parts.
fn synthetic_seeds() -> Vec<(Vec<u8>, BranchId)> {
    fn filler(n: usize, k: u8) -> Vec<u8> {
        (0..n).map(|i| (i as u8).wrapping_mul(31).wrapping_add(k)).collect()
    }
    fn transparent(b: &mut Vec<u8>) {
        b.push(1);
        b.extend(filler(36, 1));
        b.push(3);
        b.extend([0x51, 0x52, 0x53]);
        b.extend([0xff; 4]);
        b.push(2);
        b.extend(5000u64.to_le_bytes());
        b.push(1);
        b.push(0x51);
        b.extend(0u64.to_le_bytes());
        b.push(0);
    }
    fn joinsplit(b: &mut Vec<u8>, proof: usize) {
        b.push(1);
        b.extend(0u64.to_le_bytes());
        b.extend(7u64.to_le_bytes());
        b.extend(filler(288 + proof + 1202, 9));
        b.extend(filler(96, 3));
    }
    let mut out = Vec::new();
    let mut v1 = 1u32.to_le_bytes().to_vec();
    transparent(&mut v1);
    v1.extend(0u32.to_le_bytes());
    out.push((v1, BranchId::Sprout));
    let mut v2 = 2u32.to_le_bytes().to_vec();
    transparent(&mut v2);
    v2.extend(0u32.to_le_bytes());
    joinsplit(&mut v2, 296);
    out.push((v2, BranchId::Sprout));
    let mut v3 = (3u32 | 1 << 31).to_le_bytes().to_vec();
    v3.extend(0x03C48270u32.to_le_bytes());
    transparent(&mut v3);
    v3.extend(0u64.to_le_bytes());
    joinsplit(&mut v3, 296);
    out.push((v3, BranchId::Overwinter));
    let mut v4 = (4u32 | 1 << 31).to_le_bytes().to_vec();
    v4.extend(0x892F2085u32.to_le_bytes());
    transparent(&mut v4);
    v4.extend(0u64.to_le_bytes());
    v4.extend(0u64.to_le_bytes());
    v4.extend([0, 0]);
    joinsplit(&mut v4, 192);
    out.push((v4, BranchId::Sapling));
    out
}

fn gen_tx(n: usize, out: &str) -> Result<()> {
    let seeds = load_tx_seeds()?;
    let raw: Vec<Vec<u8>> = seeds.iter().map(|s| s.0.clone()).collect();
    for (b, br) in &seeds {
        if tx_verdict(b, *br) != "1" {
            bail!("seed transaction does not parse");
        }
    }
    eprintln!("{} seed transactions", seeds.len());
    let mut rng = Rng::seeded(0x7a);
    let mut o = Out::new();
    for _ in 0..n {
        let (s, br) = &seeds[rng.below(seeds.len())];
        let (kind, b) = mutate(&mut rng, s, &raw);
        let v = tx_verdict(&b, *br);
        o.push(&kind, &b, v);
    }
    o.save(out)
}

fn block_verdict(b: &[u8], branch: BranchId) -> String {
    let mut c = Cursor::new(b);
    let Ok(h) = BlockHeader::read(&mut c) else { return "0".into() };
    if h.solution.len() != 1344 {
        return "0".into();
    }
    let Ok(count) = CompactSize::read(&mut c) else { return "0".into() };
    for _ in 0..count {
        if Transaction::read(&mut c, branch).is_err() {
            return "0".into();
        }
    }
    if c.position() as usize == b.len() { format!("1 {count}") } else { "0".into() }
}

fn gen_block(n: usize, out: &str) -> Result<()> {
    let blocks = load_blocks()?;
    let raw: Vec<Vec<u8>> = blocks.iter().flat_map(|b| b.txs.clone()).collect();
    let mut rng = Rng::seeded(0xb1);
    let mut o = Out::new();
    for _ in 0..n {
        let s = &blocks[rng.below(blocks.len())];
        let branch = BranchId::for_height(&MainNetwork, BlockHeight::from_u32(s.height));
        let (kind, b) = match rng.below(6) {
            0 => {
                // Tx count rewritten (too many / too few / non-canonical / huge).
                let mut b = s.bytes[..HEADER_LEN].to_vec();
                let mut c = Cursor::new(&s.bytes[HEADER_LEN..]);
                let cnt = CompactSize::read(&mut c).unwrap();
                let rest = &s.bytes[HEADER_LEN + c.position() as usize..];
                let newc = [cnt.wrapping_sub(1), cnt + 1, 0, 0x0200_0000, 0x0200_0001][rng.below(5)];
                if rng.below(4) == 0 {
                    b.push(254);
                    b.extend((newc as u32).to_le_bytes());
                } else {
                    let mut w = Vec::new();
                    CompactSize::write(&mut w, newc.min(0x0200_0000) as usize).ok();
                    if newc > 0x0200_0000 {
                        w = vec![254];
                        w.extend((newc as u32).to_le_bytes());
                    }
                    b.extend(w);
                }
                b.extend(rest);
                ("tx_count".to_string(), b)
            }
            _ => {
                let (k, b) = mutate(&mut rng, &s.bytes, &raw);
                (k, b)
            }
        };
        let v = block_verdict(&b, branch);
        o.push(&format!("{kind}@{}", s.height), &b, v);
    }
    o.save(out)
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let n: usize = args.get(2).map(|s| s.parse()).transpose()?.unwrap_or(1000);
    let out = args.get(3).cloned().unwrap_or_else(|| format!("../data/{}", args[1]));
    match args.get(1).map(String::as_str) {
        Some("cs") => gen_cs(n, &out),
        Some("hdr") => gen_hdr(n, &out),
        Some("frame") => gen_frame(n, &out),
        Some("tx") => gen_tx(n, &out),
        Some("block") => gen_block(n, &out),
        _ => {
            let _ = std::io::stderr().write_all(b"usage: harden-oracle cs|hdr|frame|tx|block N [OUT]\n");
            Ok(())
        }
    }
}
