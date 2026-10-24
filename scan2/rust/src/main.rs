//! Test vectors and the CPU baseline for the Bend GPU trial-decryption scanner.
//!
//! `gen N`   writes out/batch_N.bin   = ivk (32 B LE) || N × (epk 32 B || enc_ciphertext[0..4])
//!                  out/expected_N.txt = indices whose compact plaintext lead byte decrypts to 0x03
//!                                      (what the GPU filter must output), with the truly-ours ones
//!                  out/debug.txt      = per-stage intermediates for the first records
//!                  out/full_N.bin     = N × (nf 32 B || cmx 32 B || epk 32 B || enc_ciphertext[0..52])
//!                                      for orchard's own batch API
//! `bench N` runs the independent ECDH/KDF/ChaCha pipeline (pasta_curves, blake2b_simd,
//!           chacha20) over the batch, 1 thread and all threads.
//! `bench-orchard N` runs orchard's batch trial decryption
//!           (zcash_note_encryption::batch::try_compact_note_decryption with a prepared ivk)
//!           over full_N.bin, 1 thread and all threads.

use std::{fs, io::Write, time::Instant};

use anyhow::{ensure, Result};
use chacha20::{
    cipher::{KeyIvInit, StreamCipher, StreamCipherSeek},
    ChaCha20,
};
use pasta_curves::{
    arithmetic::CurveAffine,
    group::{ff::PrimeField, Curve, Group, GroupEncoding},
};
use orchard::{
    keys::{FullViewingKey, PreparedIncomingViewingKey, Scope, SpendingKey},
    note::{ExtractedNoteCommitment, Nullifier, RandomSeed, Rho},
    note_encryption::{CompactAction, IronwoodDomain, IronwoodNoteEncryption},
    value::NoteValue,
    Note, NoteVersion,
};
use pasta_curves::pallas;
use zcash_note_encryption::{Domain, EphemeralKeyBytes};

fn rand32() -> [u8; 32] {
    let mut b = [0u8; 32];
    getrandom::fill(&mut b).unwrap();
    b
}

fn rand_field() -> [u8; 32] {
    let mut b = rand32();
    b[31] &= 0x3f;
    b
}

fn wallet(seed: u8) -> FullViewingKey {
    let mut s = [seed; 32];
    loop {
        if let Some(sk) = Option::<SpendingKey>::from(SpendingKey::from_bytes(s)) {
            return FullViewingKey::from(&sk);
        }
        s[0] = s[0].wrapping_add(1);
    }
}

struct Out {
    action: CompactAction,
    epk: [u8; 32],
    ct: [u8; 52],
    ours: bool,
}

fn make_output(fvk: &FullViewingKey, ours: bool) -> Out {
    let addr = fvk.address_at(0u32, Scope::External);
    loop {
        let rho_b = rand_field();
        let rho = Option::<Rho>::from(Rho::from_bytes(&rho_b)).unwrap();
        let Some(rseed) = Option::<RandomSeed>::from(RandomSeed::from_bytes(rand32(), &rho)) else { continue };
        let v = u64::from_le_bytes(rand32()[..8].try_into().unwrap()) % 1_000_000_000;
        let Some(note) = Option::<Note>::from(Note::from_parts(addr, NoteValue::from_raw(v), rho, rseed, NoteVersion::V3)) else {
            continue;
        };
        let enc = IronwoodNoteEncryption::new(None, note, [0u8; 512]);
        let ct = enc.encrypt_note_plaintext();
        let epk = IronwoodDomain::epk_bytes(enc.epk());
        let cmx = ExtractedNoteCommitment::from(note.commitment());
        let nf = Option::<Nullifier>::from(Nullifier::from_bytes(&rho_b)).unwrap();
        let ct52: [u8; 52] = ct.0[..52].try_into().unwrap();
        let action = CompactAction::from_parts(nf, cmx, EphemeralKeyBytes(epk.0), ct52);
        return Out { action, epk: epk.0, ct: ct52, ours };
    }
}

/// Independent re-implementation of the filter the GPU computes: ECDH, KDF, ChaCha20 block 1.
struct Stages {
    epk_y: [u8; 32],
    shared: [u8; 32],
    key: [u8; 32],
    ks: [u8; 4],
    lead: u8,
}

fn stages(ivk: &[u8; 32], epk: &[u8; 32], ct0: &[u8; 4]) -> Stages {
    let p = pallas::Affine::from_bytes(epk).unwrap();
    let s = pallas::Scalar::from_repr(*ivk).unwrap();
    let shared = (pallas::Point::from(p) * s).to_affine().to_bytes();
    let key = blake2b_simd::Params::new()
        .hash_length(32)
        .personal(b"Zcash_OrchardKDF")
        .to_state()
        .update(&shared)
        .update(epk)
        .finalize();
    let key: [u8; 32] = key.as_bytes().try_into().unwrap();
    let mut ks = [0u8; 4];
    let mut c = ChaCha20::new(&key.into(), &[0u8; 12].into());
    c.seek(64u32);
    c.apply_keystream(&mut ks);
    let coords = p.coordinates().unwrap();
    Stages { epk_y: coords.y().to_repr(), shared, key, ks, lead: ct0[0] ^ ks[0] }
}

fn read_batch(n: usize) -> Result<([u8; 32], Vec<([u8; 32], [u8; 4])>)> {
    let b = fs::read(format!("out/batch_{n}.bin"))?;
    ensure!(b.len() == 32 + n * 36);
    let ivk: [u8; 32] = b[..32].try_into().unwrap();
    let recs = b[32..].chunks_exact(36).map(|c| (c[..32].try_into().unwrap(), c[32..].try_into().unwrap())).collect();
    Ok((ivk, recs))
}

fn gen(n: usize) -> Result<()> {
    fs::create_dir_all("out")?;
    let me = wallet(42);
    let others: Vec<FullViewingKey> = (1..9).map(wallet).collect();
    let ivk = me.to_ivk(Scope::External);
    let ivk_bytes: [u8; 32] = ivk.to_bytes()[32..].try_into().unwrap();
    let prepared = PreparedIncomingViewingKey::new(&ivk);

    let mut bin = ivk_bytes.to_vec();
    let mut full = Vec::with_capacity(n * 148);
    let mut expected = Vec::new();
    let mut ours_idx = Vec::new();
    let mut dbg = fs::File::create("out/debug.txt")?;
    writeln!(dbg, "ivk {}", hex::encode(ivk_bytes))?;
    for i in 0..n {
        let ours = rand32()[0] < 4; // ~1.6% of outputs are ours
        let fvk = if ours { &me } else { &others[i % others.len()] };
        let o = make_output(fvk, ours);
        let (epk, ct) = (o.epk, o.ct);
        let ct4: [u8; 4] = ct[..4].try_into().unwrap();
        bin.extend_from_slice(&epk);
        bin.extend_from_slice(&ct4);
        full.extend_from_slice(&o.action.nullifier().to_bytes());
        full.extend_from_slice(&o.action.cmx().to_bytes());
        full.extend_from_slice(&epk);
        full.extend_from_slice(&ct);

        let st = stages(&ivk_bytes, &epk, &ct4);
        let _ = &ct;
        let domain = IronwoodDomain::for_compact_action(&o.action);
        let decrypted = zcash_note_encryption::try_compact_note_decryption(&domain, &prepared, &o.action).is_some();
        ensure!(decrypted == o.ours, "orchard decryption disagrees at {i}");
        if o.ours {
            ensure!(st.lead == 0x03, "independent stages disagree with orchard at {i}");
            ours_idx.push(i);
        }
        if st.lead == 0x03 {
            expected.push(i);
        }
        if i < 8 {
            writeln!(
                dbg,
                "rec {i} ours={} epk {} epk_y {} ct4 {} shared {} key {} ks4 {} lead {:02x}",
                o.ours,
                hex::encode(epk),
                hex::encode(st.epk_y),
                hex::encode(ct4),
                hex::encode(st.shared),
                hex::encode(st.key),
                hex::encode(st.ks),
                st.lead
            )?;
        }
    }
    // Field arithmetic vectors (canonical LE): a, b, a*b mod p, a^-1, sqrt(a^3 + 5) if any.
    for _ in 0..4 {
        let a = pallas::Base::from_repr(rand_field()).unwrap();
        let b = pallas::Base::from_repr(rand_field()).unwrap();
        writeln!(dbg, "fmul {} {} {}", hex::encode(a.to_repr()), hex::encode(b.to_repr()), hex::encode((a * b).to_repr()))?;
    }
    let g = pallas::Point::generator().to_affine();
    let gc = g.coordinates().unwrap();
    writeln!(dbg, "gen x {} y {}", hex::encode(gc.x().to_repr()), hex::encode(gc.y().to_repr()))?;
    let k = pallas::Scalar::from_repr(ivk_bytes).unwrap();
    let kg = (pallas::Point::from(g) * k).to_affine().coordinates().unwrap();
    writeln!(dbg, "ivk*gen x {} y {}", hex::encode(kg.x().to_repr()), hex::encode(kg.y().to_repr()))?;

    fs::write(format!("out/batch_{n}.bin"), &bin)?;
    fs::write(format!("out/full_{n}.bin"), &full)?;
    let mut e = fs::File::create(format!("out/expected_{n}.txt"))?;
    writeln!(e, "filter_hits {}", expected.len())?;
    writeln!(e, "{}", expected.iter().map(|x| x.to_string()).collect::<Vec<_>>().join(" "))?;
    writeln!(e, "ours {}", ours_idx.len())?;
    writeln!(e, "{}", ours_idx.iter().map(|x| x.to_string()).collect::<Vec<_>>().join(" "))?;
    println!("wrote {n} outputs: {} ours, {} pass the lead-byte filter", ours_idx.len(), expected.len());
    Ok(())
}

/// Baseline: what a wallet does today. The compact outputs are decrypted with
/// orchard's own code (ECDH + KDF + ChaCha20 + lead byte, then full note validation
/// on hits). We reuse the batch file (which carries only 4 ciphertext bytes), so the
/// baseline times the same per-output cryptography via the independent pipeline,
/// plus orchard's PreparedIncomingViewingKey agreement.
fn bench(n: usize, threads: usize) -> Result<()> {
    let (ivk, recs) = read_batch(n)?;
    let run = |chunk: &[([u8; 32], [u8; 4])]| -> usize {
        chunk.iter().filter(|(epk, ct4)| stages(&ivk, epk, ct4).lead == 0x03).count()
    };
    let t = Instant::now();
    let hits = if threads <= 1 {
        run(&recs)
    } else {
        let per = recs.len().div_ceil(threads);
        std::thread::scope(|s| {
            let hs: Vec<_> = recs.chunks(per).map(|c| s.spawn(move || run(c))).collect();
            hs.into_iter().map(|h| h.join().unwrap()).sum()
        })
    };
    let dt = t.elapsed();
    println!(
        "rust baseline threads={threads}: {n} outputs in {:.3}s = {:.0} outputs/s ({hits} filter hits)",
        dt.as_secs_f64(),
        n as f64 / dt.as_secs_f64()
    );
    Ok(())
}

/// orchard's own batch trial decryption, as wallets run it: ECDH with a prepared
/// (precomputed) ivk, batched normalization, KDF, ChaCha20, and full note validation
/// for every output whose lead byte passes.
fn bench_orchard(n: usize, threads: usize) -> Result<()> {
    let me = wallet(42);
    let ivk = me.to_ivk(Scope::External);
    let (file_ivk, _) = read_batch(n)?;
    ensure!(ivk.to_bytes()[32..] == file_ivk, "wallet(42) ivk differs from the batch file");
    let prepared = PreparedIncomingViewingKey::new(&ivk);
    let b = fs::read(format!("out/full_{n}.bin"))?;
    ensure!(b.len() == n * 148);
    let outs: Vec<(IronwoodDomain, CompactAction)> = b
        .chunks_exact(148)
        .map(|c| {
            let nf = Option::<Nullifier>::from(Nullifier::from_bytes(c[..32].try_into().unwrap())).unwrap();
            let cmx = Option::<ExtractedNoteCommitment>::from(ExtractedNoteCommitment::from_bytes(c[32..64].try_into().unwrap())).unwrap();
            let a = CompactAction::from_parts(nf, cmx, EphemeralKeyBytes(c[64..96].try_into().unwrap()), c[96..148].try_into().unwrap());
            (IronwoodDomain::for_compact_action(&a), a)
        })
        .collect();
    let ivks = [prepared];
    let run = |chunk: &[(IronwoodDomain, CompactAction)]| -> usize {
        zcash_note_encryption::batch::try_compact_note_decryption(&ivks, chunk).iter().filter(|r| r.is_some()).count()
    };
    let t = Instant::now();
    let found = if threads <= 1 {
        run(&outs)
    } else {
        let per = outs.len().div_ceil(threads);
        std::thread::scope(|s| {
            let hs: Vec<_> = outs.chunks(per).map(|c| s.spawn(move || run(c))).collect();
            hs.into_iter().map(|h| h.join().unwrap()).sum()
        })
    };
    let dt = t.elapsed();
    println!(
        "orchard batch API threads={threads}: {n} outputs in {:.3}s = {:.0} outputs/s ({found} notes found)",
        dt.as_secs_f64(),
        n as f64 / dt.as_secs_f64()
    );
    Ok(())
}

fn main() -> Result<()> {
    let a: Vec<String> = std::env::args().collect();
    let n: usize = a.get(2).map(|s| s.parse()).transpose()?.unwrap_or(4096);
    match a.get(1).map(String::as_str) {
        Some("gen") => gen(n),
        Some("bench") => {
            bench(n, 1)?;
            bench(n, std::thread::available_parallelism()?.get())
        }
        Some("bench-orchard") => {
            bench_orchard(n, 1)?;
            bench_orchard(n, std::thread::available_parallelism()?.get())
        }
        _ => anyhow::bail!("usage: gen N | bench N | bench-orchard N"),
    }
}
