//! node/bend oracle: parses real mainnet blocks with zcash_primitives 0.31 and prints the
//! same lines `blockdelta` prints (see ../README.md), so the two can be diffed byte for byte.
//!
//! usage: delta-oracle <height>...   (reads ../data/<h>.bin; header compared with itself)
//! The `sigops` count is this oracle's own port of zcashd's CScript::GetSigOpCount(false)
//! (zcash_primitives has none): an independent re-implementation, not official code.
use anyhow::Result;
use sha2::{Digest, Sha256};
use std::io::Cursor;
use zcash_primitives::transaction::components::orchard::bundle_version_for_branch;
use zcash_primitives::transaction::{Transaction, TxVersion};
use zcash_protocol::consensus::{BlockHeight, BranchId, MainNetwork};

const HDR: usize = 1487;

fn sha256d(b: &[u8]) -> [u8; 32] {
    Sha256::digest(Sha256::digest(b)).into()
}
fn disp(b: &[u8]) -> String {
    let mut v = b.to_vec();
    v.reverse();
    hex::encode(v)
}
fn varint(b: &[u8], i: &mut usize) -> u64 {
    let t = b[*i];
    *i += 1;
    let (n, v) = match t {
        0xfd => (2, u16::from_le_bytes(b[*i..*i + 2].try_into().unwrap()) as u64),
        0xfe => (4, u32::from_le_bytes(b[*i..*i + 4].try_into().unwrap()) as u64),
        x => (0, x as u64),
    };
    *i += n;
    v
}
fn merkle(mut level: Vec<[u8; 32]>) -> [u8; 32] {
    while level.len() > 1 {
        if level.len() % 2 == 1 {
            level.push(*level.last().unwrap());
        }
        level = level.chunks(2).map(|p| sha256d(&[p[0], p[1]].concat())).collect();
    }
    level[0]
}
/// zcashd CScript::GetSigOpCount(fAccurate = false).
fn sigops(s: &[u8]) -> u32 {
    let (mut pc, mut n) = (0usize, 0u32);
    while pc < s.len() {
        let op = s[pc];
        pc += 1;
        if op <= 0x4e {
            let (hl, size) = match op {
                0x4c => (1, if pc + 1 <= s.len() { s[pc] as usize } else { break }),
                0x4d => (2, if pc + 2 <= s.len() { u16::from_le_bytes([s[pc], s[pc + 1]]) as usize } else { break }),
                0x4e => (4, if pc + 4 <= s.len() { u32::from_le_bytes(s[pc..pc + 4].try_into().unwrap()) as usize } else { break }),
                x => (0, x as usize),
            };
            pc += hl;
            if s.len() - pc < size {
                break;
            }
            pc += size;
        }
        if op == 0xac || op == 0xad {
            n += 1;
        } else if op == 0xae || op == 0xaf {
            n += 20;
        }
    }
    n
}

fn main() -> Result<()> {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../data");
    for h in std::env::args().skip(1) {
        let height: u32 = h.parse()?;
        let raw = std::fs::read(dir.join(format!("{h}.bin")))?;
        let hdr = &raw[..HDR];
        let branch = BranchId::for_height(&MainNetwork, BlockHeight::from_u32(height));
        let mut i = HDR;
        let n = varint(&raw, &mut i) as usize;
        let (mut ids, mut body) = (Vec::new(), String::new());
        for k in 0..n {
            let start = i;
            let mut cur = Cursor::new(&raw[start..]);
            let tx = Transaction::read(&mut cur, branch)?;
            i = start + cur.position() as usize;
            let txid: [u8; 32] = *tx.txid().as_ref();
            ids.push(txid);
            let ver = tx.version();
            let (v, ow) = match ver { TxVersion::Sprout(v) => (v, 0), _ => (ver.header() & 0x7fff_ffff, 1) };
            let br: u32 = if v >= 5 { u32::from(tx.consensus_branch_id()) } else { 0 };
            let mut so = 0u32;
            let mut lines = String::new();
            if let Some(t) = tx.transparent_bundle() {
                for (j, x) in t.vin.iter().enumerate() {
                    let ss: &[u8] = &x.script_sig().0 .0;
                    so += sigops(ss);
                    if x.prevout().hash() == &[0u8; 32] && x.prevout().n() == u32::MAX {
                        lines += &format!("cb {} {}\n", hex::encode(ss), x.sequence());
                    } else {
                        lines += &format!("in {j} {} {} {}\n", disp(x.prevout().hash()), x.prevout().n(), x.sequence());
                    }
                }
                for (j, o) in t.vout.iter().enumerate() {
                    let sp: &[u8] = &o.script_pubkey().0 .0;
                    so += sigops(sp);
                    lines += &format!("out {j} {} {}\n", u64::from(o.value()), hex::encode(sp));
                }
            }
            if let Some(s) = tx.sprout_bundle() {
                for j in &s.joinsplits {
                    let (nf, cm) = (j.nullifiers(), j.commitments());
                    lines += &format!("js {} {} {} {} {} {} {}\n", i64::from(j.vpub_old()), i64::from(j.vpub_new()),
                        hex::encode(j.anchor()), hex::encode(nf[0]), hex::encode(nf[1]), hex::encode(cm[0]), hex::encode(cm[1]));
                }
            }
            if let Some(s) = tx.sapling_bundle() {
                let (sp, op) = (s.shielded_spends(), s.shielded_outputs());
                if !sp.is_empty() || !op.is_empty() {
                    lines += &format!("sap {} {} {}\n", i64::from(*s.value_balance()), sp.len(), op.len());
                    for x in sp {
                        lines += &format!("ss {} {}\n", hex::encode(x.anchor().to_bytes()), hex::encode(x.nullifier().0));
                    }
                    for x in op {
                        lines += &format!("so {}\n", hex::encode(x.cmu().to_bytes()));
                    }
                }
            }
            for (name, tag, pool, b) in [("orch", "oa", orchard::ValuePool::Orchard, tx.orchard_bundle()),
                                         ("iw", "ia", orchard::ValuePool::Ironwood, tx.ironwood_bundle())] {
                if let Some(b) = b {
                    let bv = bundle_version_for_branch(tx.consensus_branch_id(), pool).expect("bundle version");
                    let fl = b.flags().to_byte(bv).expect("flags");
                    lines += &format!("{name} {} {} {:02x} {}\n", i64::from(*b.value_balance()), hex::encode(b.anchor().to_bytes()), fl, b.actions().len());
                    for a in b.actions() {
                        lines += &format!("{tag} {} {}\n", hex::encode(a.nullifier().to_bytes()), hex::encode(a.cmx().to_bytes()));
                    }
                }
            }
            body += &format!("tx {k} {} v {v} ow {ow} grp {:08x} br {br:08x} lock {} exp {} size {} sigops {so}\n",
                disp(&txid), ver.version_group_id(), tx.lock_time(), u32::from(tx.expiry_height()), i - start);
            body += &lines;
        }
        assert_eq!(i, raw.len());
        let mr = merkle(ids);
        println!("block {h} {} {} time {} bits {:08x} size {} txs {n} header MATCH merkle {}",
            disp(&sha256d(hdr)), disp(&hdr[4..36]), u32::from_le_bytes(hdr[100..104].try_into()?),
            u32::from_le_bytes(hdr[104..108].try_into()?), raw.len(), if mr == hdr[36..68] { "MATCH" } else { "MISMATCH" });
        print!("{body}");
        println!("end {h}");
    }
    Ok(())
}
