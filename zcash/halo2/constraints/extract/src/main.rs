//! extract <prenu62|nu62|nu63> <out.json>
//!
//! For one Orchard circuit version (orchard 0.16 / halo2_gadgets 0.6, the crates whose
//! `OrchardCircuitVersion` VKs Zebend verifies mainnet bundles with):
//! 1. builds one honest Action witness (real keys, notes, Merkle path, nullifier, ...),
//! 2. synthesizes it once through `zebend_cs::Recorder` (configure + floor planner, the
//!    same calls keygen makes), recording regions, cells, names, values, selectors,
//!    fixed cells, copies,
//! 3. checks the witness with halo2's MockProver,
//! 4. rebuilds the verifying key from the recorded fixed values / selectors / copies and
//!    compares its pinned representation with `orchard::circuit::VerifyingKey::build`'s,
//! 5. writes {cs (uncompressed), vk_cs (compressed, as in the VK), layout, checks} as JSON.
use std::fs;

use ff::{Field, FromUniformBytes, PrimeField};
use halo2_proofs::{dev::MockProver, plonk::zebend_cs};
use orchard::{
    builder::SpendInfo,
    circuit::{Circuit, OrchardCircuitVersion, VerifyingKey},
    keys::{FullViewingKey, Scope, SpendingKey},
    note::{ExtractedNoteCommitment, RandomSeed, Rho},
    tree::{MerkleHashOrchard, MerklePath},
    value::{NoteValue, ValueCommitTrapdoor},
    Note, NoteVersion,
};
use pasta_curves::{pallas, Fp};
use rand::{rngs::StdRng, Rng, SeedableRng};

fn rand_fp(rng: &mut StdRng) -> Fp {
    let mut w = [0u8; 64];
    rng.fill_bytes(&mut w);
    Fp::from_uniform_bytes(&w)
}

fn note(rng: &mut StdRng, recipient: orchard::Address, v: u64, rho: Rho) -> Note {
    loop {
        let mut b = [0u8; 32];
        rng.fill_bytes(&mut b);
        let rseed = RandomSeed::from_bytes(b, &rho);
        if rseed.is_none().into() {
            continue;
        }
        let n = Note::from_parts(recipient, NoteValue::from_raw(v), rho, rseed.unwrap(), NoteVersion::V2);
        if n.is_some().into() {
            return n.unwrap();
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let (tag, out) = (args[1].as_str(), args[2].as_str());
    let seed: u64 = args.get(3).map(|s| s.parse().unwrap()).unwrap_or(20261027);
    let version = match tag {
        "prenu62" => OrchardCircuitVersion::InsecurePreNu6_2,
        "nu62" => OrchardCircuitVersion::FixedPostNu6_2,
        "nu63" => OrchardCircuitVersion::PostNu6_3,
        _ => panic!("version"),
    };
    let mut rng = StdRng::seed_from_u64(seed);

    // --- one honest Action witness
    let sk = SpendingKey::from_bytes([7u8; 32]).unwrap();
    let fvk = FullViewingKey::from(&sk);
    let sender = fvk.address_at(0u32, Scope::External);
    let rho_old = Rho::from_bytes(&rand_fp(&mut rng).to_repr()).unwrap();
    let old = note(&mut rng, sender, 1_000_000, rho_old);
    let nf = old.nullifier(&fvk);
    let rho_new = Rho::from_bytes(&nf.to_bytes()).unwrap();
    let sk2 = SpendingKey::from_bytes([9u8; 32]).unwrap();
    let recipient = FullViewingKey::from(&sk2).address_at(3u32, Scope::External);
    let new = note(&mut rng, recipient, 400_000, rho_new);
    let auth: [MerkleHashOrchard; 32] = std::array::from_fn(|_| {
        MerkleHashOrchard::from_bytes(&rand_fp(&mut rng).to_repr()).unwrap()
    });
    let pos: u32 = rng.next_u32();
    let path = MerklePath::from_parts(pos, auth);
    let anchor = path.root(ExtractedNoteCommitment::from(old.commitment()));
    let spend = SpendInfo::new(fvk, old, path).unwrap();
    let alpha = pallas::Scalar::random(&mut rng);
    let rcv = loop {
        let mut b = [0u8; 32];
        rng.fill_bytes(&mut b);
        b[31] &= 0x0f;
        let t = ValueCommitTrapdoor::from_bytes(b);
        if t.is_some().into() {
            break t.unwrap();
        }
    };
    let circuit = Circuit::from_action_context(spend, new, alpha, rcv, version).unwrap();

    // instance rows read by the circuit: anchor, enable flags, disableCrossAddress = 0;
    // the rest are filled from the cells constrained to them.
    let mut inst = vec![Fp::ZERO; 10];
    inst[0] = Fp::from_repr(anchor.to_bytes()).unwrap();
    inst[7] = Fp::ONE;
    inst[8] = Fp::ONE;
    let (cs, mut rec) = zebend_cs::record(&circuit, 11, vec![inst.clone()]).unwrap();
    for cp in rec.copies.iter() {
        for (a, b) in [(cp.left, cp.right), (cp.right, cp.left)] {
            if a.0 == halo2_proofs::plonk::Any::Instance && b.0 == halo2_proofs::plonk::Any::Advice {
                inst[a.2] = rec.advice[b.1][b.2].as_ref().unwrap().value;
            }
        }
    }
    rec.instance = vec![inst.clone()];

    // --- MockProver on the same witness
    let mock = MockProver::run(11, &circuit, vec![inst.clone()]).unwrap();
    let mock_ok = match mock.verify() {
        Ok(()) => true,
        Err(e) => {
            eprintln!("MockProver: {} failures, first: {:?}", e.len(), e.first());
            false
        }
    };

    // --- VK reconstruction from the recorded layout
    let vk = VerifyingKey::build(version);
    let rebuilt = zebend_cs::rebuild_vk_pinned(vk.oracle_params(), &cs, &rec);
    let real = zebend_cs::vk_pinned(vk.oracle_vk());
    let vk_match = rebuilt == real;
    eprintln!(
        "[{tag}] regions {} copies {} mock_ok {mock_ok} vk_match {vk_match} (pinned {} bytes)",
        rec.regions.len(),
        rec.copies.len(),
        real.len()
    );

    let json = format!(
        "{{\"version\":\"{tag}\",\"crates\":\"orchard 0.16.0 (vendored), halo2_gadgets 0.6.0, halo2_proofs 0.4.0\",\"seed\":{seed},\"mock_ok\":{mock_ok},\"vk_match\":{vk_match},\n\"cs\":{},\n\"vk_cs\":{},\n\"layout\":{}}}\n",
        zebend_cs::cs_json(&cs),
        zebend_cs::cs_json(zebend_cs::vk_cs(vk.oracle_vk())),
        zebend_cs::layout_json(&rec)
    );
    fs::write(out, json).unwrap();
    // the VK's transcript-relevant digest, for binding to zcash/halo2/verifier (tools/vkbind.py)
    fs::write(format!("{out}.vk.json"), zebend_cs::vk_digest_json(vk.oracle_vk())).unwrap();
    // negative control: the VK rebuilt with one copy constraint fewer must NOT match
    let mut fewer = zebend_cs::Recorder::new(&cs, 11, rec.instance.clone());
    fewer.fixed = rec.fixed.clone();
    fewer.selectors = rec.selectors.clone();
    fewer.copies = rec.copies[1..].to_vec();
    let control = zebend_cs::rebuild_vk_pinned(vk.oracle_params(), &cs, &fewer) != real;
    eprintln!("[{tag}] negative control (one copy dropped -> different VK): {control}");
    assert!(control);
    if !(mock_ok && vk_match) {
        std::process::exit(1);
    }
}
