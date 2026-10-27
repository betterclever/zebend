//! zcash/block oracle: parses real mainnet blocks with zcash_primitives and checks the
//! header's hashMerkleRoot and hashBlockCommitments (ZIP 244) against Rust recomputation.
//!
//! usage: block-oracle <height>...   (reads ../data/<h>.bin and ../data/<h>.json)
//! writes ../data/<h>.expected (txids, auth digests, roots, as the Bend program prints them)
//! and ../data/<h>.hist (the 32-byte chain history root, internal byte order: oracle input).

use anyhow::{anyhow, ensure, Result};
use sha2::{Digest, Sha256};
use std::io::Cursor;
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::{BlockHeight, BranchId, MainNetwork};

const HEADER_LEN: usize = 1487;

fn sha256d(b: &[u8]) -> [u8; 32] {
    Sha256::digest(Sha256::digest(b)).into()
}

fn blake(personal: &[u8; 16], data: &[u8]) -> [u8; 32] {
    let h = blake2b_simd::Params::new().hash_length(32).personal(personal).hash(data);
    h.as_bytes().try_into().unwrap()
}

fn read_varint(b: &[u8], i: &mut usize) -> u64 {
    let t = b[*i];
    *i += 1;
    let (n, v) = match t {
        0xfd => (2, u16::from_le_bytes(b[*i..*i + 2].try_into().unwrap()) as u64),
        0xfe => (4, u32::from_le_bytes(b[*i..*i + 4].try_into().unwrap()) as u64),
        0xff => (8, u64::from_le_bytes(b[*i..*i + 8].try_into().unwrap())),
        x => (0, x as u64),
    };
    *i += n;
    v
}

/// Bitcoin-style Merkle root: SHA-256d of concatenated pairs, last node duplicated on odd levels.
fn merkle_root(mut level: Vec<[u8; 32]>) -> [u8; 32] {
    while level.len() > 1 {
        if level.len() % 2 == 1 {
            level.push(*level.last().unwrap());
        }
        level = level.chunks(2).map(|p| sha256d(&[p[0], p[1]].concat())).collect();
    }
    level[0]
}

/// ZIP 244 hashAuthDataRoot: padded to a power of two with [0; 32] leaves, BLAKE2b-256 "ZcashAuthDatHash".
fn auth_root(leaves: &[[u8; 32]]) -> [u8; 32] {
    let mut level: Vec<[u8; 32]> = leaves.to_vec();
    level.resize(leaves.len().next_power_of_two(), [0u8; 32]);
    while level.len() > 1 {
        level = level.chunks(2).map(|p| blake(b"ZcashAuthDatHash", &[p[0], p[1]].concat())).collect();
    }
    level[0]
}

fn rev(hexs: &str) -> Result<[u8; 32]> {
    let mut v = hex::decode(hexs)?;
    v.reverse();
    v.try_into().map_err(|_| anyhow!("not 32 bytes"))
}

fn main() -> Result<()> {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../data");
    for h in std::env::args().skip(1) {
        let height: u32 = h.parse()?;
        let raw = std::fs::read(dir.join(format!("{h}.bin")))?;
        let rpc: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(dir.join(format!("{h}.json")))?)?;
        let hdr = &raw[..HEADER_LEN];
        let branch = BranchId::for_height(&MainNetwork, BlockHeight::from_u32(height));
        let mut i = HEADER_LEN;
        let n = read_varint(&raw, &mut i) as usize;
        let (mut txids, mut auths, mut out) = (Vec::new(), Vec::new(), String::new());
        let mut versions = std::collections::BTreeMap::<u32, usize>::new();
        for k in 0..n {
            let start = i;
            let mut cur = Cursor::new(&raw[start..]);
            let tx = Transaction::read(&mut cur, branch)?;
            i = start + cur.position() as usize;
            let v = u32::from_le_bytes(raw[start..start + 4].try_into()?) & 0x7fff_ffff;
            *versions.entry(v).or_default() += 1;
            let txid: [u8; 32] = *tx.txid().as_ref();
            // ZIP 244: v1-v4 transactions contribute the placeholder [0xff; 32].
            let auth: [u8; 32] = if v >= 5 { tx.auth_commitment().as_bytes().try_into()? } else { [0xff; 32] };
            out += &format!("tx {k} v{v} bytes {} txid {} auth {}\n", i - start, hex::encode(txid), hex::encode(auth));
            txids.push(txid);
            auths.push(auth);
        }
        ensure!(i == raw.len(), "{h}: {} trailing bytes", raw.len() - i);
        // txids against the node's own list (RPC hex is byte-reversed)
        let rpc_txids: Vec<[u8; 32]> = rpc["tx"].as_array().unwrap().iter().map(|t| rev(t.as_str().unwrap())).collect::<Result<_>>()?;
        ensure!(rpc_txids == txids, "{h}: txids differ from the node's list");

        let mr = merkle_root(txids.clone());
        let ar = auth_root(&auths);
        let hist = rev(rpc["chainhistoryroot"].as_str().unwrap())?;
        let commit = blake(b"ZcashBlockCommit", &[hist, ar, [0u8; 32]].concat());
        let block_hash = sha256d(hdr);
        ensure!(block_hash == rev(rpc["hash"].as_str().unwrap())?, "{h}: block hash");
        let ok_m = mr == hdr[36..68];
        let ok_a = ar == rev(rpc["authdataroot"].as_str().unwrap())?;
        let ok_c = commit == hdr[68..100];
        out += &format!("block {h} hash {} txs {n}\n", hex::encode(block_hash));
        out += &format!("merkle {} {}\n", hex::encode(mr), if ok_m { "MATCH" } else { "MISMATCH" });
        out += &format!("authroot {}\n", hex::encode(ar));
        out += &format!("commitments {} {}\n", hex::encode(commit), if ok_c { "MATCH" } else { "MISMATCH" });
        std::fs::write(dir.join(format!("{h}.expected")), &out)?;
        std::fs::write(dir.join(format!("{h}.hist")), hist)?;
        println!("{h}: {n} txs {versions:?}  merkle {}  authroot==node {}  commitments {}",
            if ok_m { "MATCH" } else { "MISMATCH" }, ok_a, if ok_c { "MATCH" } else { "MISMATCH" });
    }
    Ok(())
}
