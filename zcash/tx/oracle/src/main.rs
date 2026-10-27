//! Ground truth for the Bend transaction layer (zcash/tx).
//!
//! Fetches real mainnet transactions carrying Orchard and/or Ironwood bundles from
//! lightwalletd, parses them with zcash_primitives 0.31, and writes per-transaction
//! vectors: the raw bytes, every ZIP 244 digest, the shielded sighash, each action's
//! fields, the RedPallas signatures and the Halo 2 public inputs.
//!
//! Everything written here is self-checked against the chain itself:
//!   * the txid recomputed by zcash_primitives equals the txid lightwalletd indexed;
//!   * the shielded sighash (computed here directly from ZIP 244, including the
//!     transparent-input amounts/scripts fetched from the previous transactions)
//!     makes every on-chain spend-auth signature and the binding signature verify;
//!   * the 10-row instance vector computed here per action makes the real mainnet
//!     Halo 2 proof verify under the official halo2_proofs verifier.

use std::{collections::HashMap, fmt::Write as _, fs, path::Path};

use anyhow::{anyhow, bail, ensure, Context, Result};
use blake2b_simd::Params;
use ff::PrimeField;
use group::{Curve, Group, GroupEncoding};
use orchard::{
    bundle::{Authorized, BundleVersion},
    ProtocolVersion,
    circuit::{OrchardCircuitVersion, VerifyingKey},
    primitives::redpallas::{self, Binding, SpendAuth},
};
use pasta_curves::{arithmetic::CurveAffine, arithmetic::CurveExt, pallas, vesta};
use tonic::transport::{Channel, ClientTlsConfig};
use zcash_primitives::transaction::{txid::TxIdDigester, Transaction};
use zcash_protocol::consensus::{BlockHeight, BranchId, MainNetwork};

const OUT: &str = "../mainnet";
const SERVICE: &str = "/cash.z.wallet.sdk.rpc.CompactTxStreamer";

// ---------------------------------------------------------------- lightwalletd

#[derive(Clone, PartialEq, prost::Message)]
struct BlockId {
    #[prost(uint64, tag = "1")]
    height: u64,
    #[prost(bytes = "vec", tag = "2")]
    hash: Vec<u8>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct BlockRange {
    #[prost(message, optional, tag = "1")]
    start: Option<BlockId>,
    #[prost(message, optional, tag = "2")]
    end: Option<BlockId>,
    #[prost(int32, repeated, tag = "3")]
    pool_types: Vec<i32>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct ChainSpec {}
#[derive(Clone, PartialEq, prost::Message)]
struct CompactAction {
    #[prost(bytes = "vec", tag = "1")]
    nullifier: Vec<u8>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct CompactTx {
    #[prost(bytes = "vec", tag = "2")]
    txid: Vec<u8>,
    #[prost(message, repeated, tag = "4")]
    sapling_spends: Vec<CompactAction>,
    #[prost(message, repeated, tag = "5")]
    sapling_outputs: Vec<CompactAction>,
    #[prost(message, repeated, tag = "6")]
    actions: Vec<CompactAction>,
    #[prost(message, repeated, tag = "9")]
    ironwood_actions: Vec<CompactAction>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct CompactBlock {
    #[prost(uint64, tag = "2")]
    height: u64,
    #[prost(message, repeated, tag = "7")]
    vtx: Vec<CompactTx>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct TxFilter {
    #[prost(message, optional, tag = "1")]
    block: Option<BlockId>,
    #[prost(uint64, tag = "2")]
    index: u64,
    #[prost(bytes = "vec", tag = "3")]
    hash: Vec<u8>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct RawTransaction {
    #[prost(bytes = "vec", tag = "1")]
    data: Vec<u8>,
    #[prost(uint64, tag = "2")]
    height: u64,
}

struct Lwd(tonic::client::Grpc<Channel>);

impl Lwd {
    async fn connect(url: &str) -> Result<Self> {
        let ep = Channel::from_shared(url.to_string())?.tls_config(ClientTlsConfig::new().with_webpki_roots())?;
        Ok(Self(tonic::client::Grpc::new(ep.connect().await?)))
    }
    async fn unary<Q, R>(&mut self, m: &'static str, q: Q) -> Result<R>
    where
        Q: prost::Message + Send + Sync + 'static,
        R: prost::Message + Default + Send + Sync + 'static,
    {
        self.0.ready().await?;
        let path = format!("{SERVICE}/{m}").parse()?;
        Ok(self.0.unary(tonic::Request::new(q), path, tonic_prost::ProstCodec::default()).await?.into_inner())
    }
    async fn tip(&mut self) -> Result<u64> {
        Ok(self.unary::<_, BlockId>("GetLatestBlock", ChainSpec {}).await?.height)
    }
    async fn raw_tx(&mut self, txid: &[u8; 32]) -> Result<RawTransaction> {
        self.unary("GetTransaction", TxFilter { block: None, index: 0, hash: txid.to_vec() }).await
    }
    async fn blocks(&mut self, start: u64, end: u64) -> Result<Vec<CompactBlock>> {
        self.0.ready().await?;
        let path = format!("{SERVICE}/GetBlockRange").parse()?;
        let req = BlockRange {
            start: Some(BlockId { height: start, hash: vec![] }),
            end: Some(BlockId { height: end, hash: vec![] }),
            pool_types: vec![2, 3, 4], // SAPLING, ORCHARD, IRONWOOD
        };
        let mut s = self
            .0
            .server_streaming::<_, CompactBlock, _>(tonic::Request::new(req), path, tonic_prost::ProstCodec::default())
            .await?
            .into_inner();
        let mut out = vec![];
        while let Some(b) = s.message().await? {
            out.push(b);
        }
        Ok(out)
    }
}

// ---------------------------------------------------------------- hashing helpers

fn h32(personal: &[u8; 16], parts: &[&[u8]]) -> [u8; 32] {
    let mut s = Params::new().hash_length(32).personal(personal).to_state();
    for p in parts {
        s.update(p);
    }
    s.finalize().as_bytes().try_into().unwrap()
}

fn compact_size(n: usize, out: &mut Vec<u8>) {
    match n {
        0..=252 => out.push(n as u8),
        253..=0xffff => {
            out.push(253);
            out.extend_from_slice(&(n as u16).to_le_bytes())
        }
        0x10000..=0xffff_ffff => {
            out.push(254);
            out.extend_from_slice(&(n as u32).to_le_bytes())
        }
        _ => {
            out.push(255);
            out.extend_from_slice(&(n as u64).to_le_bytes())
        }
    }
}

// ---------------------------------------------------------------- vectors

struct Out {
    lines: String,
}
impl Out {
    fn put(&mut self, name: &str, bytes: &[u8]) {
        writeln!(self.lines, "{name} {}", hex::encode(bytes)).unwrap();
    }
    fn num(&mut self, name: &str, n: u64) {
        writeln!(self.lines, "{name} {n}").unwrap();
    }
}

fn affine_xy(bytes: &[u8; 32]) -> Result<(pallas::Base, pallas::Base)> {
    let p = Option::<pallas::Point>::from(pallas::Point::from_bytes(bytes)).ok_or_else(|| anyhow!("not a point"))?;
    let c: pasta_curves::arithmetic::Coordinates<pallas::Affine> =
        Option::from(p.to_affine().coordinates()).ok_or_else(|| anyhow!("identity"))?;
    Ok((*c.x(), *c.y()))
}

/// The `disableCrossAddress` instance row (orchard `Instance::from_parts` + `Flags::from_byte`).
fn cross_address_disabled(version: BundleVersion, flags: u8) -> bool {
    let enabled = match version.protocol_version() {
        ProtocolVersion::InsecureV1 | ProtocolVersion::V2 => true,
        ProtocolVersion::V3 => flags & 0b100 != 0,
    };
    !enabled
}

struct Vks(HashMap<String, VerifyingKey>);
impl Vks {
    fn get(&mut self, v: OrchardCircuitVersion) -> &VerifyingKey {
        self.0.entry(format!("{v:?}")).or_insert_with(|| VerifyingKey::build(v))
    }
}

#[derive(Default)]
struct Tally {
    txs: usize,
    v5: usize,
    v6: usize,
    orchard_bundles: usize,
    ironwood_bundles: usize,
    actions: usize,
    with_transparent_inputs: usize,
    with_sapling: usize,
}

#[tokio::main]
async fn main() -> Result<()> {
    let want_ironwood: usize = std::env::args().nth(1).map(|s| s.parse()).transpose()?.unwrap_or(12);
    let want_orchard: usize = std::env::args().nth(2).map(|s| s.parse()).transpose()?.unwrap_or(8);
    let url = std::env::var("LWD").unwrap_or_else(|_| "https://zec.rocks:443".into());
    fs::create_dir_all(OUT)?;
    let mut lwd = Lwd::connect(&url).await?;
    let tip = lwd.tip().await?;
    eprintln!("tip {tip}");

    // 1. Pick candidates in buckets, so the sample spans tx versions, protocol eras
    //    (and therefore circuit versions), pools, and Sapling/transparent content.
    let _ = (want_ironwood, want_orchard);
    struct Bucket {
        name: &'static str,
        from: u64,
        floor: u64,
        quota: usize,
        per_block: usize,
        pick: fn(usize, usize, usize) -> bool, // (orchard, ironwood, sapling) -> take?
    }
    let buckets = [
        Bucket { name: "v6 ironwood", from: tip, floor: 3_428_143, quota: 10, per_block: 2, pick: |_, i, _| i > 0 },
        Bucket { name: "v6 orchard (withdraw-only)", from: tip, floor: 3_428_143, quota: 6, per_block: 2, pick: |o, i, _| o > 0 && i == 0 },
        Bucket { name: "with sapling", from: tip, floor: 3_300_000, quota: 4, per_block: 1, pick: |o, i, s| s > 0 && o + i > 0 },
        Bucket { name: "v5 NU6.2 (fixed circuit)", from: 3_428_142, floor: 3_364_600, quota: 5, per_block: 1, pick: |o, _, _| o > 0 },
        Bucket { name: "v5 pre-NU6.2 (historical circuit)", from: 3_364_599, floor: 3_146_400, quota: 4, per_block: 1, pick: |o, _, _| o > 0 },
    ];
    let mut picks: Vec<([u8; 32], u64, &'static str)> = vec![];
    for bk in &buckets {
        let mut got = 0;
        let mut end = bk.from;
        while got < bk.quota && end > bk.floor {
            let start = end.saturating_sub(199).max(bk.floor);
            for b in lwd.blocks(start, end).await? {
                let mut in_block = 0;
                for tx in &b.vtx {
                    let (o, i, s) = (tx.actions.len(), tx.ironwood_actions.len(), tx.sapling_spends.len() + tx.sapling_outputs.len());
                    if got < bk.quota && in_block < bk.per_block && (bk.pick)(o, i, s) && tx.txid.len() == 32 {
                        let id: [u8; 32] = tx.txid.clone().try_into().unwrap();
                        if picks.iter().all(|p| p.0 != id) {
                            picks.push((id, b.height, bk.name));
                            got += 1;
                            in_block += 1;
                        }
                    }
                }
            }
            end = start - 1;
        }
        eprintln!("bucket {:<36} {got}/{} (scanned down to {})", bk.name, bk.quota, end + 1);
    }

    let mut vks = Vks(HashMap::new());
    let mut prev_cache: HashMap<[u8; 32], Transaction> = HashMap::new();
    let mut tally = Tally::default();
    let mut index = String::new();
    // Value-commitment and spend-auth generators (GroupHash), exported for the Bend side.
    let v_gen = pallas::Point::hash_to_curve("z.cash:Orchard-cv")(b"v");
    let r_gen = pallas::Point::hash_to_curve("z.cash:Orchard-cv")(b"r");
    let g_spend = pallas::Point::hash_to_curve("z.cash:Orchard")(b"G");
    {
        let mut o = Out { lines: String::new() };
        o.put("V", &v_gen.to_bytes());
        o.put("R", &r_gen.to_bytes());
        o.put("G_spendauth", &g_spend.to_bytes());
        fs::write(Path::new(OUT).join("constants.txt"), o.lines)?;
    }

    for (i, (txid_lwd, _h, bucket)) in picks.iter().enumerate() {
        let raw = lwd.raw_tx(txid_lwd).await.with_context(|| format!("GetTransaction {}", hex::encode(txid_lwd)))?;
        let height = raw.height;
        let branch = BranchId::for_height(&MainNetwork, BlockHeight::from_u32(height as u32));
        let tx = Transaction::read(&raw.data[..], branch)?;
        let txid: [u8; 32] = *tx.txid().as_ref();
        ensure!(&txid == txid_lwd, "txid mismatch for tx {i}");

        let mut o = Out { lines: String::new() };
        o.num("height", height);
        writeln!(o.lines, "bucket {bucket}").unwrap();
        o.put("txid", &txid);
        let ver = tx.version();
        o.put("header", &ver.header().to_le_bytes());
        o.put("version_group_id", &ver.version_group_id().to_le_bytes());
        o.put("branch_id", &u32::from(tx.consensus_branch_id()).to_le_bytes());
        o.put("lock_time", &tx.lock_time().to_le_bytes());
        o.put("expiry_height", &u32::from(tx.expiry_height()).to_le_bytes());
        let is_v6 = ver.has_ironwood();
        if is_v6 {
            tally.v6 += 1
        } else {
            tally.v5 += 1
        }

        let d = tx.digest(TxIdDigester);
        o.put("header_digest", d.header_digest().as_bytes());
        let t_txid = {
            let mut parts: Vec<&[u8]> = vec![];
            if let Some(td) = d.transparent_digests() {
                o.put("prevouts_digest", td.prevouts_digest.as_bytes());
                o.put("sequence_digest", td.sequence_digest.as_bytes());
                o.put("outputs_digest", td.outputs_digest.as_bytes());
                parts = vec![td.prevouts_digest.as_bytes(), td.sequence_digest.as_bytes(), td.outputs_digest.as_bytes()];
            }
            h32(b"ZTxIdTranspaHash", &parts)
        };
        o.put("transparent_digest", &t_txid);
        let sapling = d
            .sapling_digest()
            .map(|h| h.as_bytes().to_vec())
            .unwrap_or_else(|| h32(b"ZTxIdSaplingHash", &[]).to_vec());
        if d.sapling_digest().is_some() {
            tally.with_sapling += 1
        }
        o.put("sapling_digest", &sapling);
        let orch_empty: &[u8; 16] = if is_v6 { b"ZTxIdOrchardH_v6" } else { b"ZTxIdOrchardHash" };
        let orchard_d = d.orchard_digest().map(|h| h.as_bytes().to_vec()).unwrap_or_else(|| h32(orch_empty, &[]).to_vec());
        o.put("orchard_digest", &orchard_d);
        let ironwood_d = d
            .ironwood_digest()
            .map(|h| h.as_bytes().to_vec())
            .unwrap_or_else(|| h32(b"ZTxIdIronwd_H_v6", &[]).to_vec());
        if is_v6 {
            o.put("ironwood_digest", &ironwood_d);
        }

        // Shielded sighash (ZIP 244 S.2 with SIGHASH_ALL), computed here from first principles.
        let mut personal = *b"ZcashTxHash_\0\0\0\0";
        personal[12..].copy_from_slice(&u32::from(tx.consensus_branch_id()).to_le_bytes());
        let mut amounts_bytes = vec![];
        let mut scripts_bytes = vec![];
        let t_sig = match (tx.transparent_bundle(), d.transparent_digests()) {
            (Some(b), Some(td)) if !b.is_coinbase() && !b.vin.is_empty() => {
                tally.with_transparent_inputs += 1;
                for vin in &b.vin {
                    let ph: [u8; 32] = *vin.prevout().hash();
                    if !prev_cache.contains_key(&ph) {
                        let pr = lwd.raw_tx(&ph).await?;
                        let pb = BranchId::for_height(&MainNetwork, BlockHeight::from_u32(pr.height as u32));
                        prev_cache.insert(ph, Transaction::read(&pr.data[..], pb)?);
                    }
                    let prev = &prev_cache[&ph];
                    let out = prev
                        .transparent_bundle()
                        .and_then(|pb| pb.vout.get(vin.prevout().n() as usize))
                        .ok_or_else(|| anyhow!("prevout not found"))?;
                    amounts_bytes.extend_from_slice(&i64::try_from(u64::from(out.value()))?.to_le_bytes());
                    let code = &out.script_pubkey().0 .0;
                    compact_size(code.len(), &mut scripts_bytes);
                    scripts_bytes.extend_from_slice(code);
                }
                let amounts = h32(b"ZTxTrAmountsHash", &[&amounts_bytes]);
                let scripts = h32(b"ZTxTrScriptsHash", &[&scripts_bytes]);
                let txin = h32(b"Zcash___TxInHash", &[]);
                o.put("amounts_digest", &amounts);
                o.put("scripts_digest", &scripts);
                h32(
                    b"ZTxIdTranspaHash",
                    &[
                        &[1u8],
                        td.prevouts_digest.as_bytes(),
                        &amounts,
                        &scripts,
                        td.sequence_digest.as_bytes(),
                        td.outputs_digest.as_bytes(),
                        &txin,
                    ],
                )
            }
            _ => t_txid,
        };
        o.put("transparent_sig_digest", &t_sig);
        let mut top: Vec<&[u8]> = vec![d.header_digest().as_bytes(), &t_sig, &sapling, &orchard_d];
        if is_v6 {
            top.push(&ironwood_d);
        }
        let sighash = h32(&personal, &top);
        o.put("sighash", &sighash);
        // Cross-check the txid from the same digests.
        let mut top_id: Vec<&[u8]> = vec![d.header_digest().as_bytes(), &t_txid, &sapling, &orchard_d];
        if is_v6 {
            top_id.push(&ironwood_d);
        }
        ensure!(h32(&personal, &top_id) == txid, "txid tree recomputation mismatch");

        // Transparent-input context the Bend side needs for the sighash: exactly the bytes hashed.
        let mut ctx = vec![];
        ctx.extend_from_slice(&(amounts_bytes.len() as u32).to_le_bytes());
        ctx.extend_from_slice(&amounts_bytes);
        ctx.extend_from_slice(&(scripts_bytes.len() as u32).to_le_bytes());
        ctx.extend_from_slice(&scripts_bytes);

        // Orchard-protocol bundles: signatures, binding key, instances, proof.
        let bundles: Vec<(&str, &orchard::Bundle<Authorized, zcash_protocol::value::ZatBalance>)> =
            [("orchard", tx.orchard_bundle()), ("ironwood", tx.ironwood_bundle())]
                .into_iter()
                .filter_map(|(n, b)| b.map(|b| (n, b)))
                .collect();
        for (pool, b) in &bundles {
            if *pool == "orchard" {
                tally.orchard_bundles += 1
            } else {
                tally.ironwood_bundles += 1
            }
            let bv = b.bundle_version();
            let flags = b.flags().to_byte(bv).ok_or_else(|| anyhow!("flags"))?;
            let vb: i64 = (*b.value_balance()).into();
            o.num(&format!("{pool}.actions"), b.actions().len() as u64);
            o.put(&format!("{pool}.flags"), &[flags]);
            o.put(&format!("{pool}.value_balance"), &vb.to_le_bytes());
            o.put(&format!("{pool}.anchor"), &b.anchor().to_bytes());
            o.num(&format!("{pool}.proof_len"), b.authorization().proof().as_ref().len() as u64);
            let mut cv_sum = pallas::Point::identity();
            let mut instances: Vec<[vesta::Scalar; 10]> = vec![];
            for (j, a) in b.actions().iter().enumerate() {
                tally.actions += 1;
                let p = format!("{pool}.a{j}");
                let cv = a.cv_net().to_bytes();
                let rk: [u8; 32] = a.rk().into();
                o.put(&format!("{p}.cv"), &cv);
                o.put(&format!("{p}.nf"), &a.nullifier().to_bytes());
                o.put(&format!("{p}.rk"), &rk);
                o.put(&format!("{p}.cmx"), &a.cmx().to_bytes());
                o.put(&format!("{p}.epk"), &a.encrypted_note().epk_bytes);
                let sig: [u8; 64] = a.authorization().into();
                o.put(&format!("{p}.spend_auth_sig"), &sig);
                let vk = redpallas::VerificationKey::<SpendAuth>::try_from(rk).map_err(|_| anyhow!("rk"))?;
                let ok = vk.verify(&sighash, a.authorization()).is_ok();
                ensure!(ok, "spend-auth signature {p} does not verify under our sighash");
                o.num(&format!("{p}.spend_auth_ok"), ok as u64);
                cv_sum += Option::<pallas::Point>::from(pallas::Point::from_bytes(&cv)).unwrap();
                // Halo 2 public inputs, computed independently of orchard's Instance type.
                let (cvx, cvy) = affine_xy(&cv)?;
                let (rkx, rky) = affine_xy(&rk)?;
                let fe = |b: [u8; 32]| Option::<pallas::Base>::from(pallas::Base::from_repr(b)).unwrap();
                let inst = [
                    fe(b.anchor().to_bytes()),
                    cvx,
                    cvy,
                    fe(a.nullifier().to_bytes()),
                    rkx,
                    rky,
                    fe(a.cmx().to_bytes()),
                    pallas::Base::from((flags & 1) as u64),
                    pallas::Base::from(((flags >> 1) & 1) as u64),
                    pallas::Base::from(cross_address_disabled(bv, flags) as u64),
                ];
                for (k, v) in inst.iter().enumerate() {
                    o.put(&format!("{p}.instance[{k}]"), &v.to_repr());
                }
                instances.push(inst);
            }
            // Binding signature: bvk = Σ cv_net − ValueCommit_0(v_balance) = Σ cv_net − [v_balance] V.
            let vbs = if vb >= 0 { pallas::Scalar::from(vb as u64) } else { -pallas::Scalar::from(vb.unsigned_abs()) };
            let bvk = (cv_sum - v_gen * vbs).to_bytes();
            o.put(&format!("{pool}.bvk"), &bvk);
            let bsig: [u8; 64] = b.authorization().binding_signature().into();
            o.put(&format!("{pool}.binding_sig"), &bsig);
            let bvk_key = redpallas::VerificationKey::<Binding>::try_from(bvk).map_err(|_| anyhow!("bvk"))?;
            ensure!(bvk_key.verify(&sighash, b.authorization().binding_signature()).is_ok(), "binding sig for {pool}");
            o.num(&format!("{pool}.binding_ok"), 1);

            // The real proof, with OUR instance vectors, through the official halo2 verifier.
            let vk = vks.get(bv.circuit_version());
            let cols: Vec<Vec<&[vesta::Scalar]>> = instances.iter().map(|i| vec![&i[..]]).collect();
            let refs: Vec<&[&[vesta::Scalar]]> = cols.iter().map(|c| &c[..]).collect();
            let proof = b.authorization().proof().as_ref();
            let strategy = halo2_proofs::plonk::SingleVerifier::new(vk.oracle_params());
            let mut tr = halo2_proofs::transcript::Blake2bRead::<_, vesta::Affine, _>::init(proof);
            let res = halo2_proofs::plonk::verify_proof(vk.oracle_params(), vk.oracle_vk(), strategy, &refs, &mut tr);
            ensure!(res.is_ok(), "{pool} proof rejected with our instances: {res:?}");
            ensure!(b.verify_proof(vk).is_ok(), "{pool} official verify_proof failed");
            o.num(&format!("{pool}.proof_ok"), 1);
            fs::write(Path::new(OUT).join(format!("tx_{i}.{pool}.proof.bin")), proof)?;
        }
        if bundles.is_empty() {
            bail!("tx {i} has no Orchard-protocol bundle");
        }
        fs::write(Path::new(OUT).join(format!("tx_{i}.bin")), &raw.data)?;
        fs::write(Path::new(OUT).join(format!("tx_{i}.ctx")), &ctx)?;
        fs::write(Path::new(OUT).join(format!("tx_{i}.txt")), &o.lines)?;
        tally.txs += 1;
        writeln!(
            index,
            "tx_{i} height {height} v{} bytes {} orchard {} ironwood {} t_inputs {} t_outputs {} sapling {} circuit {:?} [{bucket}]",
            if is_v6 { 6 } else { 5 },
            raw.data.len(),
            tx.orchard_bundle().map_or(0, |b| b.actions().len()),
            tx.ironwood_bundle().map_or(0, |b| b.actions().len()),
            tx.transparent_bundle().map_or(0, |b| b.vin.len()),
            tx.transparent_bundle().map_or(0, |b| b.vout.len()),
            tx.sapling_bundle().map_or(0, |b| b.shielded_spends().len() + b.shielded_outputs().len()),
            tx.orchard_bundle().or(tx.ironwood_bundle()).map(|b| b.bundle_version().circuit_version()),
        )
        .unwrap();
        eprintln!("tx_{i}: height {height} v{} ok", if is_v6 { 6 } else { 5 });
    }
    fs::write(Path::new(OUT).join("index.txt"), &index)?;
    println!(
        "txs {} (v5 {}, v6 {}), orchard bundles {}, ironwood bundles {}, actions {}, with transparent inputs {}, with sapling {}",
        tally.txs,
        tally.v5,
        tally.v6,
        tally.orchard_bundles,
        tally.ironwood_bundles,
        tally.actions,
        tally.with_transparent_inputs,
        tally.with_sapling
    );
    println!("all txids, sighashes, spend-auth sigs, binding sigs and Halo 2 instance vectors self-checked against the chain");
    Ok(())
}
