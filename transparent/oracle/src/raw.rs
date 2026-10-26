//! Byte-level helpers: the transparent layout of a raw transaction (offsets, for the legacy
//! sighash and for tampering), the ZTV1 record format, and script classification.
use anyhow::{anyhow, bail, ensure, Result};
use sha2::{Digest, Sha256};

pub fn sha256d(b: &[u8]) -> [u8; 32] {
    Sha256::digest(Sha256::digest(b)).into()
}

pub fn read_cs(b: &[u8], p: &mut usize) -> Result<u64> {
    let f = *b.get(*p).ok_or_else(|| anyhow!("eof"))?;
    *p += 1;
    let n = match f {
        0xfd => 2,
        0xfe => 4,
        0xff => 8,
        _ => return Ok(f as u64),
    };
    ensure!(*p + n <= b.len(), "eof");
    let mut v = 0u64;
    for i in 0..n {
        v |= (b[*p + i] as u64) << (8 * i);
    }
    *p += n;
    Ok(v)
}

pub fn write_cs(out: &mut Vec<u8>, n: u64) {
    if n < 0xfd {
        out.push(n as u8);
    } else if n <= 0xffff {
        out.push(0xfd);
        out.extend_from_slice(&(n as u16).to_le_bytes());
    } else if n <= 0xffff_ffff {
        out.push(0xfe);
        out.extend_from_slice(&(n as u32).to_le_bytes());
    } else {
        out.push(0xff);
        out.extend_from_slice(&n.to_le_bytes());
    }
}

fn u32le(b: &[u8], p: usize) -> Result<u32> {
    ensure!(p + 4 <= b.len(), "eof");
    Ok(u32::from_le_bytes(b[p..p + 4].try_into().unwrap()))
}

#[derive(Clone, Debug)]
pub struct TIn {
    pub start: usize, // offset of the outpoint
    pub prev_hash: [u8; 32],
    pub prev_n: u32,
    pub script_off: usize,
    pub script_len: usize,
    pub seq_off: usize,
    pub seq: u32,
}

#[derive(Clone, Debug)]
pub struct TOut {
    pub value_off: usize,
    pub value: i64,
    pub script_off: usize,
    pub script_len: usize,
}

#[derive(Clone, Debug)]
pub struct Layout {
    pub header: u32,
    pub version: u32,
    pub vin: Vec<TIn>,
    pub vout: Vec<TOut>,
    pub vout_end: usize,
    pub lock_off: usize,
    pub lock_time: u32,
}

impl Layout {
    pub fn is_coinbase(&self) -> bool {
        self.vin.len() == 1 && self.vin[0].prev_hash == [0; 32] && self.vin[0].prev_n == 0xffff_ffff
    }
}

/// Parse the transparent part of a raw transaction of any version (1..6).
pub fn layout(tx: &[u8]) -> Result<Layout> {
    let header = u32le(tx, 0)?;
    let overwintered = header >> 31 == 1;
    let version = header & 0x7fff_ffff;
    let mut p = match (overwintered, version) {
        (false, 1 | 2) => 4,
        (true, 3 | 4) => 8,
        (true, 5 | 6) => 20,
        _ => bail!("unsupported tx header {header:#x}"),
    };
    let nin = read_cs(tx, &mut p)? as usize;
    ensure!(nin <= tx.len() / 41 + 1, "bad vin count");
    let mut vin = Vec::with_capacity(nin);
    for _ in 0..nin {
        let start = p;
        ensure!(p + 36 <= tx.len(), "eof");
        let prev_hash: [u8; 32] = tx[p..p + 32].try_into().unwrap();
        let prev_n = u32le(tx, p + 32)?;
        p += 36;
        let sl = read_cs(tx, &mut p)? as usize;
        ensure!(p + sl + 4 <= tx.len(), "eof");
        let script_off = p;
        p += sl;
        let seq = u32le(tx, p)?;
        vin.push(TIn { start, prev_hash, prev_n, script_off, script_len: sl, seq_off: p, seq });
        p += 4;
    }
    let nout = read_cs(tx, &mut p)? as usize;
    ensure!(nout <= tx.len() / 9 + 1, "bad vout count");
    let mut vout = Vec::with_capacity(nout);
    for _ in 0..nout {
        ensure!(p + 8 <= tx.len(), "eof");
        let value = i64::from_le_bytes(tx[p..p + 8].try_into().unwrap());
        let value_off = p;
        p += 8;
        let sl = read_cs(tx, &mut p)? as usize;
        ensure!(p + sl <= tx.len(), "eof");
        vout.push(TOut { value_off, value, script_off: p, script_len: sl });
        p += sl;
    }
    let vout_end = p;
    let lock_off = if version >= 5 { 12 } else { vout_end };
    let lock_time = u32le(tx, lock_off)?;
    Ok(Layout { header, version, vin, vout, vout_end, lock_off, lock_time })
}

// ---------------------------------------------------------------- script parsing

/// One parsed script element: opcode byte, pushed data (for push opcodes), byte range.
#[derive(Clone, Debug)]
pub struct Op {
    pub op: u8,
    pub data: Option<(usize, usize)>, // (offset, len) of pushed data within the script
    pub start: usize,
    pub end: usize,
}

/// Parse a script into ops; `Err(ops_so_far)` if a push runs past the end.
pub fn parse_ops(s: &[u8]) -> std::result::Result<Vec<Op>, Vec<Op>> {
    let mut ops = vec![];
    let mut p = 0;
    while p < s.len() {
        let start = p;
        let op = s[p];
        p += 1;
        let n = match op {
            0x01..=0x4b => Some(op as usize),
            0x4c => {
                if p + 1 > s.len() {
                    return Err(ops);
                }
                p += 1;
                Some(s[p - 1] as usize)
            }
            0x4d => {
                if p + 2 > s.len() {
                    return Err(ops);
                }
                p += 2;
                Some(u16::from_le_bytes([s[p - 2], s[p - 1]]) as usize)
            }
            0x4e => {
                if p + 4 > s.len() {
                    return Err(ops);
                }
                p += 4;
                Some(u32::from_le_bytes(s[p - 4..p].try_into().unwrap()) as usize)
            }
            0x00 => Some(0),
            _ => None,
        };
        let data = match n {
            Some(n) => {
                if p + n > s.len() {
                    return Err(ops);
                }
                let d = (p, n);
                p += n;
                Some(d)
            }
            None => None,
        };
        ops.push(Op { op, data, start, end: p });
    }
    Ok(ops)
}

/// zcashd's CTransactionSignatureSerializer::SerializeScriptCode body: the script with every
/// OP_CODESEPARATOR (0xab) found at an opcode boundary removed (parsing stops at the first
/// malformed push; the remaining bytes are kept).
pub fn strip_codeseparators(s: &[u8]) -> Vec<u8> {
    let ops = match parse_ops(s) {
        Ok(o) | Err(o) => o,
    };
    if !ops.iter().any(|o| o.op == 0xab) {
        return s.to_vec();
    }
    let mut out = Vec::with_capacity(s.len());
    let mut last = 0;
    for o in &ops {
        if o.op == 0xab {
            out.extend_from_slice(&s[last..o.start]);
            last = o.end;
        }
    }
    out.extend_from_slice(&s[last..]);
    out
}

// ---------------------------------------------------------------- legacy sighash (v1/v2)

/// zcashd's pre-Overwinter `SignatureHash` (Bitcoin's original algorithm plus the JoinSplit
/// fields for nVersion >= 2), RE-IMPLEMENTED here (no official crate implements it; Zebra
/// checkpoints these heights). `None` = zcashd throws (SIGHASH_SINGLE with nIn >= #vout).
pub fn legacy_sighash(tx: &[u8], lay: &Layout, n_in: usize, script_code: &[u8], hash_type: i32) -> Option<[u8; 32]> {
    let base = hash_type & 0x1f;
    let acp = hash_type & 0x80 != 0;
    if n_in >= lay.vin.len() {
        return None;
    }
    if base == 3 && n_in >= lay.vout.len() {
        return None;
    }
    let mut b = Vec::with_capacity(tx.len() + 64);
    b.extend_from_slice(&tx[0..4]);
    let code = strip_codeseparators(script_code);
    let ins: Vec<usize> = if acp { vec![n_in] } else { (0..lay.vin.len()).collect() };
    write_cs(&mut b, ins.len() as u64);
    for j in ins {
        let i = &lay.vin[j];
        b.extend_from_slice(&tx[i.start..i.start + 36]);
        if j == n_in {
            write_cs(&mut b, code.len() as u64);
            b.extend_from_slice(&code);
        } else {
            b.push(0);
        }
        let seq = if j != n_in && (base == 2 || base == 3) { 0 } else { i.seq };
        b.extend_from_slice(&seq.to_le_bytes());
    }
    let nout = match base {
        2 => 0,
        3 => n_in + 1,
        _ => lay.vout.len(),
    };
    write_cs(&mut b, nout as u64);
    for k in 0..nout {
        let o = &lay.vout[k];
        if base == 3 && k != n_in {
            b.extend_from_slice(&(-1i64).to_le_bytes());
            b.push(0);
        } else {
            b.extend_from_slice(&tx[o.value_off..o.script_off + o.script_len]);
        }
    }
    b.extend_from_slice(&lay.lock_time.to_le_bytes());
    if lay.version >= 2 {
        let js = &tx[lay.lock_off + 4..];
        let mut p = 0;
        let n_js = read_cs(js, &mut p).ok()?;
        if n_js > 0 {
            if js.len() < p + 96 {
                return None;
            }
            b.extend_from_slice(&js[..js.len() - 64]);
            b.extend_from_slice(&[0u8; 64]);
        } else {
            b.extend_from_slice(&js[..p]);
        }
    }
    b.extend_from_slice(&hash_type.to_le_bytes());
    Some(sha256d(&b))
}

/// Number of JoinSplits of a v2 tx (0 for other versions).
pub fn n_joinsplits(tx: &[u8], lay: &Layout) -> u64 {
    if lay.version != 2 {
        return 0;
    }
    let mut p = lay.lock_off + 4;
    read_cs(tx, &mut p).unwrap_or(0)
}

// ---------------------------------------------------------------- ZTV1 records

#[derive(Clone, Debug)]
pub struct Prev {
    pub amount: i64,
    pub spk: Vec<u8>,
}

#[derive(Clone, Debug)]
pub struct Record {
    pub height: u32,
    pub flags: u32,
    pub tx: Vec<u8>,
    pub prevs: Vec<Prev>,
}

impl Record {
    pub fn size(&self) -> usize {
        12 + self.tx.len() + 4 + self.prevs.iter().map(|p| 12 + p.spk.len()).sum::<usize>()
    }
}

pub fn write_file(path: &std::path::Path, recs: &[Record]) -> Result<()> {
    let mut b = Vec::new();
    b.extend_from_slice(b"ZTV1");
    b.extend_from_slice(&(recs.len() as u32).to_le_bytes());
    for r in recs {
        b.extend_from_slice(&r.height.to_le_bytes());
        b.extend_from_slice(&r.flags.to_le_bytes());
        b.extend_from_slice(&(r.tx.len() as u32).to_le_bytes());
        b.extend_from_slice(&r.tx);
        b.extend_from_slice(&(r.prevs.len() as u32).to_le_bytes());
        for p in &r.prevs {
            b.extend_from_slice(&p.amount.to_le_bytes());
            b.extend_from_slice(&(p.spk.len() as u32).to_le_bytes());
            b.extend_from_slice(&p.spk);
        }
    }
    std::fs::write(path, b)?;
    Ok(())
}

pub fn read_file(path: &std::path::Path) -> Result<Vec<Record>> {
    let b = std::fs::read(path)?;
    ensure!(b.len() >= 8 && &b[0..4] == b"ZTV1", "{}: not a ZTV1 file", path.display());
    let n = u32le(&b, 4)? as usize;
    let mut p = 8;
    let mut take = |k: usize| -> Result<&[u8]> {
        ensure!(p + k <= b.len(), "truncated ZTV1 file");
        p += k;
        Ok(&b[p - k..p])
    };
    let mut recs = Vec::with_capacity(n);
    for _ in 0..n {
        let height = u32::from_le_bytes(take(4)?.try_into().unwrap());
        let flags = u32::from_le_bytes(take(4)?.try_into().unwrap());
        let tl = u32::from_le_bytes(take(4)?.try_into().unwrap()) as usize;
        let tx = take(tl)?.to_vec();
        let np = u32::from_le_bytes(take(4)?.try_into().unwrap()) as usize;
        let mut prevs = Vec::with_capacity(np);
        for _ in 0..np {
            let amount = i64::from_le_bytes(take(8)?.try_into().unwrap());
            let sl = u32::from_le_bytes(take(4)?.try_into().unwrap()) as usize;
            prevs.push(Prev { amount, spk: take(sl)?.to_vec() });
        }
        recs.push(Record { height, flags, tx, prevs });
    }
    ensure!(p == b.len(), "trailing bytes in ZTV1 file");
    Ok(recs)
}

// ---------------------------------------------------------------- classification

pub fn is_p2pkh(s: &[u8]) -> bool {
    s.len() == 25 && s[0] == 0x76 && s[1] == 0xa9 && s[2] == 0x14 && s[23] == 0x88 && s[24] == 0xac
}
pub fn is_p2sh(s: &[u8]) -> bool {
    s.len() == 23 && s[0] == 0xa9 && s[1] == 0x14 && s[22] == 0x87
}
pub fn is_p2pk(s: &[u8]) -> bool {
    (s.len() == 35 && s[0] == 33 && s[34] == 0xac) || (s.len() == 67 && s[0] == 65 && s[66] == 0xac)
}
/// m-of-n if `s` is OP_m <pubkey>*n OP_n OP_CHECKMULTISIG.
pub fn multisig(s: &[u8]) -> Option<(u8, u8)> {
    let ops = parse_ops(s).ok()?;
    if ops.len() < 4 || ops.last()?.op != 0xae {
        return None;
    }
    let m = ops[0].op;
    let n = ops[ops.len() - 2].op;
    if !(0x51..=0x60).contains(&m) || !(0x51..=0x60).contains(&n) {
        return None;
    }
    let keys = &ops[1..ops.len() - 2];
    if keys.len() != (n - 0x50) as usize || !keys.iter().all(|o| o.data.map_or(false, |(_, l)| l == 33 || l == 65)) {
        return None;
    }
    Some((m - 0x50, n - 0x50))
}

/// Single-letter spent-script type: k=P2PKH, s=P2SH, p=P2PK, m=bare multisig, o=other.
pub fn spk_letter(s: &[u8]) -> char {
    if is_p2pkh(s) {
        'k'
    } else if is_p2sh(s) {
        's'
    } else if is_p2pk(s) {
        'p'
    } else if multisig(s).is_some() {
        'm'
    } else {
        'o'
    }
}

/// Last push of a scriptSig (the redeem script for P2SH, the pubkey for P2PKH).
pub fn last_push(sig: &[u8]) -> Option<Vec<u8>> {
    let ops = parse_ops(sig).ok()?;
    let o = ops.last()?;
    let (off, len) = o.data?;
    Some(sig[off..off + len].to_vec())
}

/// Detailed class used for the summary.
pub fn detail_class(spk: &[u8], sig: &[u8]) -> String {
    match spk_letter(spk) {
        'k' => match last_push(sig).map(|k| k.len()) {
            Some(33) => "P2PKH-compressed".into(),
            Some(65) => "P2PKH-uncompressed".into(),
            Some(n) => format!("P2PKH-keylen{n}"),
            None => "P2PKH-nokey".into(),
        },
        's' => match last_push(sig) {
            Some(rs) => {
                if let Some((m, n)) = multisig(&rs) {
                    format!("P2SH-multisig-{m}-of-{n}")
                } else if is_p2pkh(&rs) {
                    "P2SH-p2pkh".into()
                } else if is_p2pk(&rs) {
                    "P2SH-p2pk".into()
                } else {
                    format!("P2SH-other(redeem {})", hex::encode(&rs[..rs.len().min(40)]))
                }
            }
            None => "P2SH-noredeem".into(),
        },
        'p' => if spk.len() == 35 { "P2PK-compressed".into() } else { "P2PK-uncompressed".into() },
        'm' => {
            let (m, n) = multisig(spk).unwrap();
            format!("bare-multisig-{m}-of-{n}")
        }
        _ => format!("other(spk {})", hex::encode(&spk[..spk.len().min(40)])),
    }
}

pub const ERAS: &[(&str, u32, u32)] = &[
    ("preoverwinter", 1, 347_499),
    ("overwinter", 347_500, 419_199),
    ("sapling", 419_200, 653_599),
    ("blossom", 653_600, 902_999),
    ("heartwood", 903_000, 1_046_399),
    ("canopy", 1_046_400, 1_687_103),
    ("nu5", 1_687_104, 2_726_399),
    ("nu6_0", 2_726_400, 3_146_399),
    ("nu6_1", 3_146_400, 3_364_599),
    ("nu6_2", 3_364_600, 3_428_142),
    ("nu6_3", 3_428_143, u32::MAX),
];

pub fn era_of(h: u32) -> &'static str {
    ERAS.iter().find(|(_, a, b)| *a <= h && h <= *b).map(|e| e.0).unwrap_or("genesis")
}
