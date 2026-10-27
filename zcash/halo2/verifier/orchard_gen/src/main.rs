//! Orchard (post-NU6.3 circuit) inputs for the Bend Halo 2 verifier.
//!
//! Writes:
//!   ../orchard_v.bend, ../orchard_main.bend, ../orchard_bad_main.bend
//!       2-action verifier with the proof embedded (the first, constant-input version)
//!   ../orchard_dyn.bend      bundle-generic verifier (any number of actions, inputs at runtime)
//!   ../data/params_g.bin     the 2^11 IPA generators, affine x || y (64 bytes each)
//!   ../data/bundles/*.bin    one file per bundle: H0's proof and every post-NU6.3 mainnet bundle
//!                            from zcash/tx/mainnet (read-only), each also tampered (`.bad.bin`)
//!   ../data/bundles/halo2_verdicts.txt   the official halo2 verdict for every bundle file
//!   out/orchard_trace.txt    halo2's intermediates for H0's proof (our instrumented halo2 copy)

use std::fs;

use ff::PrimeField;
use halo2_proofs::{
    zebend_codegen::{bend_verifier, bend_verifier_dyn, fp_lit, item_lit},
    zebend_trace,
    plonk::{verify_proof, SingleVerifier},
    transcript::{Blake2bRead, Challenge255},
};
use orchard::circuit::{OrchardCircuitVersion, ProvingKey};
use pasta_curves::{arithmetic::CurveAffine, vesta, Fp};

const VEC: &str = "../../vectors";
const MAINNET: &str = "../../../tx/mainnet";

fn fp_hex(h: &str) -> Fp {
    let mut bytes = [0u8; 32];
    if h != "0" {
        bytes.copy_from_slice(&hex::decode(h).unwrap());
    }
    Fp::from_repr(bytes).unwrap()
}

/// H0's `instance[proof][column][row] hex` file
fn h0_instances() -> Vec<Vec<Fp>> {
    let mut out: Vec<Vec<Fp>> = vec![vec![], vec![]];
    for line in fs::read_to_string(format!("{VEC}/instances.txt")).unwrap().lines() {
        let (name, hexv) = line.split_once(' ').unwrap();
        let p: usize = name[9..10].parse().unwrap();
        out[p].push(fp_hex(hexv));
    }
    out
}

/// zcash/tx's `<pool>.a<i>.instance[<r>] hex` lines
fn tx_instances(txt: &str, pool: &str) -> Vec<Vec<Fp>> {
    let mut out: Vec<Vec<Fp>> = vec![];
    for line in txt.lines() {
        let Some((name, hexv)) = line.split_once(' ') else { continue };
        let Some(rest) = name.strip_prefix(&format!("{pool}.a")) else { continue };
        let Some((a, r)) = rest.split_once(".instance[") else { continue };
        let a: usize = a.parse().unwrap();
        let r: usize = r.trim_end_matches(']').parse().unwrap();
        while out.len() <= a {
            out.push(vec![]);
        }
        assert_eq!(out[a].len(), r);
        out[a].push(fp_hex(hexv));
    }
    out
}

fn bundle_bytes(proof: &[u8], inst: &[Vec<Fp>]) -> Vec<u8> {
    let mut b = vec![];
    b.extend((inst.len() as u32).to_le_bytes());
    b.extend((inst[0].len() as u32).to_le_bytes());
    b.extend((proof.len() as u32).to_le_bytes());
    b.extend(proof);
    for a in inst {
        for v in a {
            b.extend(v.to_repr());
        }
    }
    b
}

fn main() {
    fs::create_dir_all("out").unwrap();
    fs::create_dir_all("../data/bundles").unwrap();
    let pk = ProvingKey::build(OrchardCircuitVersion::PostNu6_3);
    let vk = pk.verifying_key();
    let (params, hvk) = (vk.oracle_params(), vk.oracle_vk());

    // official verifier (our vendored halo2_proofs 0.4: upstream logic + recording hooks)
    let verify = |proof: &[u8], inst: &[Vec<Fp>]| -> (bool, Vec<(String, String)>) {
        zebend_trace::take();
        let cols: Vec<[&[Fp]; 1]> = inst.iter().map(|a| [&a[..]]).collect();
        let all: Vec<&[&[Fp]]> = cols.iter().map(|c| &c[..]).collect();
        let mut tr = Blake2bRead::<_, vesta::Affine, Challenge255<_>>::init(proof);
        let ok = verify_proof(params, hvk, SingleVerifier::new(params), &all, &mut tr).is_ok();
        (ok, zebend_trace::take())
    };

    // H0's 2-action proof: trace + the constant-input programs
    let inst = h0_instances();
    let proof = fs::read(format!("{VEC}/proof.bin")).unwrap();
    let (ok, trace) = verify(&proof, &inst);
    assert!(ok, "halo2 rejects H0's Orchard proof");
    let txt: String = trace.iter().map(|(n, h)| format!("{n} {h}\n")).collect();
    fs::write("out/orchard_trace.txt", txt).unwrap();
    let mut bad = proof.clone();
    bad[3632] ^= 1;
    assert!(!verify(&bad, &inst).0, "halo2 accepts the tampered proof");
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

    // bundle-generic verifier + runtime inputs
    let dyn_src = bend_verifier_dyn(params, hvk, 6);
    fs::write("../orchard_dyn.bend", &dyn_src).unwrap();
    // the same verifier with H1's Pippenger MSM (lib/msm_fast.bend, window c = 8) for the final check
    let i = dyn_src.find("MSM.msm(6n, ").expect("final MSM call");
    let j = i + dyn_src[i..].find(")").unwrap();
    let args: Vec<&str> = dyn_src[i + "MSM.msm(6n, ".len()..j].split(", ").collect();
    let (ps, ss) = (args[0], args[1]);
    let fast = format!(
        "{}MF.pip(8, 0n, MF.chunks(0n, U32.from_nat(List.length(&2, V.Pt, {ps})), {ps}, {ss})){}",
        &dyn_src[..i],
        &dyn_src[j + 1..]
    )
    .replace("import ../lib/msm.bend as MSM\n", "import ../lib/msm.bend as MSM\nimport ../lib/msm_fast.bend as MF\n");
    fs::write("../orchard_dyn_fast.bend", fast).unwrap();
    let mut g = vec![];
    for p in params.get_g().iter() {
        let c = p.coordinates().unwrap();
        g.extend(c.x().to_repr());
        g.extend(c.y().to_repr());
    }
    fs::write("../data/params_g.bin", g).unwrap();

    let mut verdicts = String::new();
    let mut emit = |name: &str, proof: &[u8], inst: &[Vec<Fp>]| {
        let ok = verify(proof, inst).0;
        fs::write(format!("../data/bundles/{name}.bin"), bundle_bytes(proof, inst)).unwrap();
        // tamper: flip one bit in the middle of the proof
        let mut bad = proof.to_vec();
        let at = bad.len() / 2;
        bad[at] ^= 1;
        let bad_ok = verify(&bad, inst).0;
        fs::write(format!("../data/bundles/{name}.bad.bin"), bundle_bytes(&bad, inst)).unwrap();
        verdicts += &format!("{name} {} {}\n", ok as u8, inst.len());
        verdicts += &format!("{name}.bad {} {}\n", bad_ok as u8, inst.len());
    };
    emit("h0", &proof, &inst);
    let index = fs::read_to_string(format!("{MAINNET}/index.txt")).unwrap();
    for line in index.lines() {
        if !line.contains("circuit Some(PostNu6_3)") {
            continue;
        }
        let tx = line.split_whitespace().next().unwrap();
        let txt = fs::read_to_string(format!("{MAINNET}/{tx}.txt")).unwrap();
        for pool in ["orchard", "ironwood"] {
            let path = format!("{MAINNET}/{tx}.{pool}.proof.bin");
            let Ok(proof) = fs::read(&path) else { continue };
            let inst = tx_instances(&txt, pool);
            emit(&format!("{tx}.{pool}"), &proof, &inst);
        }
    }
    drop(emit);
    fs::write("../data/bundles/halo2_verdicts.txt", &verdicts).unwrap();
    print!("{verdicts}");

    // older circuits: the same generator on their VKs, for the v5 mainnet bundles
    for (ver, tag, label) in [
        (OrchardCircuitVersion::FixedPostNu6_2, "nu62", "circuit Some(FixedPostNu6_2)"),
        (OrchardCircuitVersion::InsecurePreNu6_2, "prenu62", "circuit Some(InsecurePreNu6_2)"),
    ] {
        let pk = ProvingKey::build(ver);
        let vk = pk.verifying_key();
        let (params, hvk) = (vk.oracle_params(), vk.oracle_vk());
        let src = bend_verifier_dyn(params, hvk, 6);
        let i = src.find("MSM.msm(6n, ").unwrap();
        let j = i + src[i..].find(")").unwrap();
        let args: Vec<&str> = src[i + "MSM.msm(6n, ".len()..j].split(", ").collect();
        let fast = format!(
            "{}MF.pip(8, 0n, MF.chunks(0n, U32.from_nat(List.length(&2, V.Pt, {})), {}, {})){}",
            &src[..i], args[0], args[0], args[1], &src[j + 1..]
        )
        .replace("import ../lib/msm.bend as MSM\n", "import ../lib/msm.bend as MSM\nimport ../lib/msm_fast.bend as MF\n");
        fs::write(format!("../orchard_dyn_{tag}.bend"), fast).unwrap();
        let dir = format!("../data/bundles_{tag}");
        fs::create_dir_all(&dir).unwrap();
        let mut verdicts = String::new();
        for line in index.lines().filter(|l| l.contains(label)) {
            let tx = line.split_whitespace().next().unwrap();
            let txt = fs::read_to_string(format!("{MAINNET}/{tx}.txt")).unwrap();
            let Ok(proof) = fs::read(format!("{MAINNET}/{tx}.orchard.proof.bin")) else { continue };
            let inst = tx_instances(&txt, "orchard");
            let ok = {
                let cols: Vec<[&[Fp]; 1]> = inst.iter().map(|a| [&a[..]]).collect();
                let all: Vec<&[&[Fp]]> = cols.iter().map(|c| &c[..]).collect();
                let mut tr = Blake2bRead::<_, vesta::Affine, Challenge255<_>>::init(&proof[..]);
                verify_proof(params, hvk, SingleVerifier::new(params), &all, &mut tr).is_ok()
            };
            let mut bad = proof.clone();
            let at = bad.len() / 2;
            bad[at] ^= 1;
            let bad_ok = {
                let cols: Vec<[&[Fp]; 1]> = inst.iter().map(|a| [&a[..]]).collect();
                let all: Vec<&[&[Fp]]> = cols.iter().map(|c| &c[..]).collect();
                let mut tr = Blake2bRead::<_, vesta::Affine, Challenge255<_>>::init(&bad[..]);
                verify_proof(params, hvk, SingleVerifier::new(params), &all, &mut tr).is_ok()
            };
            fs::write(format!("{dir}/{tx}.orchard.bin"), bundle_bytes(&proof, &inst)).unwrap();
            fs::write(format!("{dir}/{tx}.orchard.bad.bin"), bundle_bytes(&bad, &inst)).unwrap();
            verdicts += &format!("{tx}.orchard {} {}\n{tx}.orchard.bad {} {}\n", ok as u8, inst.len(), bad_ok as u8, inst.len());
        }
        fs::write(format!("{dir}/halo2_verdicts.txt"), &verdicts).unwrap();
        print!("[{tag}]\n{verdicts}");
    }
}
