//! Halo 2 oracle for the Bend verifier.
//!
//! Builds a real Ironwood (NU6.3, post-NU6.3 circuit) Orchard-protocol bundle with
//! the official `orchard` crate, proves it, and runs the official `halo2_proofs`
//! verifier with a recording hook (vendored, see vendor/halo2_proofs/src/dump.rs)
//! that captures every transcript absorb, challenge and intermediate value.
//! Writes ground-truth vectors and the generated Bend circuit description.

use std::{fs, path::Path};

use halo2_proofs::{dump, oracle_export};
use orchard::{
    builder::{Builder, BundleType},
    bundle::{Authorized, BundleVersion},
    circuit::{Instance, OrchardCircuitVersion, ProvingKey},
    keys::{FullViewingKey, Scope, SpendingKey},
    tree::Anchor,
    value::NoteValue,
    Bundle, Proof,
};
use rand::{rngs::StdRng, SeedableRng};

mod toy;

const OUT: &str = "../vectors";
const GEN: &str = "../gen";

fn write_dump(path: &Path, log: &[(String, Vec<u8>)]) {
    let mut s = String::new();
    for (name, bytes) in log {
        s.push_str(name);
        s.push(' ');
        // Labels that are text (phase markers, results) are written as-is for readability.
        if matches!(name.as_str(), "phase" | "result") || bytes.starts_with(b"msm:") {
            s.push_str(&String::from_utf8_lossy(bytes));
        } else {
            s.push_str(&hex::encode(bytes));
        }
        s.push('\n');
    }
    fs::write(path, s).unwrap();
}

fn main() {
    let mode = std::env::args().nth(1).unwrap_or_else(|| "all".into());
    fs::create_dir_all(OUT).unwrap();
    fs::create_dir_all(GEN).unwrap();
    let mut rng = StdRng::seed_from_u64(20261024);

    if mode == "toy" || mode == "all" {
        run_toy();
        if mode == "toy" {
            return;
        }
    }

    let t = std::time::Instant::now();
    let pk = ProvingKey::build(OrchardCircuitVersion::PostNu6_3);
    let vk = pk.verifying_key();
    eprintln!("keygen: {:?}", t.elapsed());

    if mode == "codegen" || mode == "all" {
        let (text, g, g_lagrange) = oracle_export::export_params_vk(vk.oracle_params(), vk.oracle_vk());
        fs::write(Path::new(OUT).join("params_vk.txt"), text).unwrap();
        fs::write(Path::new(OUT).join("params_g.bin"), g).unwrap();
        fs::write(Path::new(OUT).join("params_g_lagrange.bin"), g_lagrange).unwrap();
        fs::write(Path::new(GEN).join("orchard_cs.bend"), oracle_export::codegen_bend(vk.oracle_vk())).unwrap();
        eprintln!("wrote params_vk.txt, params_g*.bin, gen/orchard_cs.bend");
        if mode == "codegen" {
            return;
        }
    }

    // A real Ironwood bundle: two outputs, padded with dummy spends (2 actions).
    let sk = SpendingKey::from_bytes([7u8; 32]).unwrap();
    let fvk = FullViewingKey::from(&sk);
    let recipient = fvk.address_at(0u32, Scope::External);
    let version = BundleVersion::ironwood_v3();
    let mut builder = Builder::new(BundleType::DEFAULT, version, version.default_flags(), Anchor::empty_tree()).unwrap();
    builder.add_output(None, recipient, NoteValue::from_raw(314_159_265), [0u8; 512]).unwrap();
    builder.add_output(None, recipient, NoteValue::from_raw(271_828_182), [0u8; 512]).unwrap();
    let (unproven, _meta) = builder.build::<i64>(&mut rng).unwrap().unwrap();
    let t = std::time::Instant::now();
    let proven = unproven.create_proof(&pk, &mut rng).unwrap();
    eprintln!("prove ({} actions): {:?}", proven.actions().len(), t.elapsed());
    let sighash = [0x42u8; 32];
    let bundle: Bundle<Authorized, i64> = proven.apply_signatures(&mut rng, sighash, &[]).unwrap();

    let t = std::time::Instant::now();
    bundle.verify_proof(&vk).expect("official verifier rejects our proof");
    eprintln!("official verify: OK in {:?}", t.elapsed());

    let instances: Vec<Instance> = bundle
        .actions()
        .iter()
        .map(|a| a.to_instance(*bundle.flags(), *bundle.anchor()))
        .collect();
    let proof_bytes = bundle.authorization().proof().as_ref().to_vec();
    fs::write(Path::new(OUT).join("proof.bin"), &proof_bytes).unwrap();

    // Instrumented run of the same verification.
    dump::start();
    let ok = Proof::new(proof_bytes.clone()).verify(&vk, &instances);
    let log = dump::take();
    println!("instrumented verify: {:?} ({} recorded values)", ok, log.len());
    write_dump(&Path::new(OUT).join("orchard_verify.txt"), &log);
    let inst_lines: String = log
        .iter()
        .filter(|(n, _)| n.starts_with("instance["))
        .map(|(n, b)| format!("{n} {}\n", hex::encode(b)))
        .collect();
    fs::write(Path::new(OUT).join("instances.txt"), inst_lines).unwrap();

    // Codegen self-check: the generated IR, evaluated in Rust, must reproduce halo2's own values.
    let checked = oracle_export::check_codegen_against_dump(vk.oracle_vk(), &log);
    println!("codegen IR check: {checked} gate/lookup values match halo2");
    fs::write(Path::new(GEN).join("orchard_cs_selftest.bend"), oracle_export::bend_selftest(vk.oracle_vk(), &log, 0)).unwrap();

    // Tampered proof: flip one byte in the middle of the proof.
    let mut bad = proof_bytes.clone();
    let at = bad.len() / 2;
    bad[at] ^= 0x01;
    dump::start();
    let bad_ok = Proof::new(bad).verify(&vk, &instances);
    let bad_log = dump::take();
    println!("tampered verify (byte {at} flipped): {:?}", bad_ok);
    write_dump(&Path::new(OUT).join("orchard_tampered.txt"), &bad_log);
    match log.iter().zip(bad_log.iter()).position(|(a, b)| a != b) {
        Some(i) => println!(
            "tampered run first diverges at record {i}: {} ({} vs {} records total)",
            log[i].0,
            log.len(),
            bad_log.len()
        ),
        None => println!("tampered run identical prefix; lengths {} vs {}", log.len(), bad_log.len()),
    }
    println!("proof: {} bytes, {} actions", proof_bytes.len(), instances.len());
}

/// Toy circuit: same dump / export / codegen, one proof, k = 5.
fn run_toy() {
    let (params, vk, proof, public) = toy::prove();
    toy::verify(&params, &vk, &proof, &public).expect("toy proof rejected by the official verifier");
    fs::write(Path::new(OUT).join("toy_proof.bin"), &proof).unwrap();
    let (text, g, gl) = oracle_export::export_params_vk(&params, &vk);
    fs::write(Path::new(OUT).join("toy_params_vk.txt"), text).unwrap();
    fs::write(Path::new(OUT).join("toy_params_g.bin"), g).unwrap();
    fs::write(Path::new(OUT).join("toy_params_g_lagrange.bin"), gl).unwrap();
    fs::write(Path::new(GEN).join("toy_cs.bend"), oracle_export::codegen_bend(&vk)).unwrap();
    dump::start();
    let ok = toy::verify(&params, &vk, &proof, &public);
    let log = dump::take();
    write_dump(&Path::new(OUT).join("toy_verify.txt"), &log);
    let checked = oracle_export::check_codegen_against_dump(&vk, &log);
    let st = oracle_export::bend_selftest(&vk, &log, 0).replace("orchard_cs.bend", "toy_cs.bend");
    fs::write(Path::new(GEN).join("toy_cs_selftest.bend"), st).unwrap();
    let mut bad = proof.clone();
    let at = bad.len() / 2;
    bad[at] ^= 0x01;
    dump::start();
    let bad_ok = toy::verify(&params, &vk, &bad, &public);
    write_dump(&Path::new(OUT).join("toy_tampered.txt"), &dump::take());
    println!(
        "toy: verify {:?} ({} records, proof {} bytes, codegen IR check {checked}); tampered byte {at}: {:?}",
        ok,
        log.len(),
        proof.len(),
        bad_ok
    );
}
