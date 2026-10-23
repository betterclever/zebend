//! Generates `../orchard_v.bend` (the Bend Halo 2 verifier for the post-NU6.3 Orchard circuit)
//! plus `../orchard_main.bend` / `../orchard_bad_main.bend` for H0's real 2-action Ironwood proof
//! (honest, and with byte 3632 flipped), and `out/orchard_trace.txt`: halo2's own intermediate
//! values for that proof, recorded by our instrumented halo2 copy.

use std::fs;

use ff::PrimeField;
use halo2_proofs::{
    zebend_codegen::{bend_verifier, fp_lit, item_lit},
    zebend_trace,
    plonk::{verify_proof, SingleVerifier},
    transcript::{Blake2bRead, Challenge255},
};
use orchard::circuit::{OrchardCircuitVersion, ProvingKey};
use pasta_curves::{vesta, Fp};

const VEC: &str = "../../vectors";

fn instances() -> Vec<Vec<Fp>> {
    let mut out: Vec<Vec<Fp>> = vec![vec![], vec![]];
    for line in fs::read_to_string(format!("{VEC}/instances.txt")).unwrap().lines() {
        let (name, hexv) = line.split_once(' ').unwrap();
        let p: usize = name[9..10].parse().unwrap();
        let mut bytes = [0u8; 32];
        if hexv != "0" {
            bytes.copy_from_slice(&hex::decode(hexv).unwrap());
        }
        out[p].push(Fp::from_repr(bytes).unwrap());
    }
    out
}

fn main() {
    fs::create_dir_all("out").unwrap();
    let pk = ProvingKey::build(OrchardCircuitVersion::PostNu6_3);
    let vk = pk.verifying_key();
    let (params, hvk) = (vk.oracle_params(), vk.oracle_vk());
    let inst = instances();
    let proof = fs::read(format!("{VEC}/proof.bin")).unwrap();

    let verify = |proof: &[u8]| -> (bool, Vec<(String, String)>) {
        zebend_trace::take();
        let i0 = [&inst[0][..]];
        let i1 = [&inst[1][..]];
        let all: [&[&[Fp]]; 2] = [&i0, &i1];
        let mut tr = Blake2bRead::<_, vesta::Affine, Challenge255<_>>::init(proof);
        let ok = verify_proof(params, hvk, SingleVerifier::new(params), &all, &mut tr).is_ok();
        (ok, zebend_trace::take())
    };
    let (ok, trace) = verify(&proof);
    assert!(ok, "halo2 rejects H0's Orchard proof");
    let mut txt = String::new();
    for (n, h) in &trace {
        txt += &format!("{n} {h}\n");
    }
    fs::write("out/orchard_trace.txt", txt).unwrap();
    let mut bad = proof.clone();
    bad[3632] ^= 1;
    assert!(!verify(&bad).0, "halo2 accepts the tampered proof");

    fs::write("../orchard_v.bend", bend_verifier(params, hvk, 2, &[inst[0].len()], 6)).unwrap();
    let main_of = |proof: &[u8]| -> String {
        let items: Vec<String> = proof.chunks(32).map(item_lit).collect();
        let ivals: Vec<String> = inst.iter().flatten().map(|v| fp_lit(*v)).collect();
        format!(
            "import Base\nimport ../lib/words.bend as Wd\nimport ../lib/fp.bend as Fp\nimport ./vlib.bend as L\nimport ./orchard_v.bend as O\n\n\
             def PROOF() -> L.Proof:\n  L.Proof{{[{}],\n  [{}]}}\n\n\
             def main() -> IO(Unit):\n  +st = O.verify(PROOF())\n  do IO<Unit>:\n    L.print_log(L.st_log(st))\n    IO.print(\"result \" ++ U32.show(L.st_ok(st)))\n",
            items.join(",\n    "),
            ivals.join(",\n    ")
        )
    };
    fs::write("../orchard_main.bend", main_of(&proof)).unwrap();
    fs::write("../orchard_bad_main.bend", main_of(&bad)).unwrap();
    println!(
        "Orchard: proof {} bytes, {} instance values, transcript_repr {:?}; halo2 honest ok, tampered rejected; {} trace records",
        proof.len(),
        inst.iter().map(|v| v.len()).sum::<usize>(),
        hex::encode(hvk_repr(hvk)),
        trace.len()
    );
}

fn hvk_repr(vk: &halo2_proofs::plonk::VerifyingKey<vesta::Affine>) -> [u8; 32] {
    halo2_proofs::zebend_codegen::transcript_repr(vk).to_repr()
}
