//! Toy halo2 oracle for the Bend verifier: a small circuit exercising a custom gate,
//! a rotation, a lookup, copy constraints and an instance column; two proofs share one
//! transcript (as an Orchard bundle's actions do). Writes:
//!   out/toy_v.bend          generated Bend verifier module (zebend_codegen)
//!   out/toy_main.bend       honest proof + instances, prints the verifier log
//!   out/toy_bad_main.bend   the same with one proof byte flipped
//!   out/toy_trace.txt       halo2's own intermediate values, `name hex` per line

use std::fs;

use halo2_proofs::{
    circuit::{Layouter, SimpleFloorPlanner, Value},
    zebend_codegen::{bend_verifier, fp_lit, item_lit},
    zebend_trace,
    plonk::{
        create_proof, keygen_pk, keygen_vk, verify_proof, Advice, Circuit, Column, ConstraintSystem,
        Error, Instance, Selector, SingleVerifier, TableColumn,
    },
    poly::{commitment::Params, Rotation},
    transcript::{Blake2bRead, Blake2bWrite, Challenge255},
};
use pasta_curves::{vesta, Fp};
use rand::{rngs::StdRng, SeedableRng};

const K: u32 = 5;

#[derive(Clone)]
struct Cfg {
    a: Column<Advice>,
    b: Column<Advice>,
    c: Column<Advice>,
    inst: Column<Instance>,
    s_mul: Selector,
    s_chain: Selector,
    s_lk: Selector,
    table: TableColumn,
}

#[derive(Clone, Default)]
struct Toy {
    a0: Value<Fp>,
    b0: Value<Fp>,
    b1: Value<Fp>,
}

impl Circuit<Fp> for Toy {
    type Config = Cfg;
    type FloorPlanner = SimpleFloorPlanner;

    fn without_witnesses(&self) -> Self {
        Self::default()
    }

    fn configure(meta: &mut ConstraintSystem<Fp>) -> Cfg {
        let a = meta.advice_column();
        let b = meta.advice_column();
        let c = meta.advice_column();
        let inst = meta.instance_column();
        meta.enable_equality(a);
        meta.enable_equality(c);
        meta.enable_equality(inst);
        let s_mul = meta.selector();
        let s_chain = meta.selector();
        let s_lk = meta.complex_selector();
        let table = meta.lookup_table_column();
        meta.create_gate("mul", |m| {
            let s = m.query_selector(s_mul);
            let a = m.query_advice(a, Rotation::cur());
            let b = m.query_advice(b, Rotation::cur());
            let c = m.query_advice(c, Rotation::cur());
            vec![s * (a * b - c)]
        });
        meta.create_gate("chain", |m| {
            let s = m.query_selector(s_chain);
            let a_next = m.query_advice(a, Rotation::next());
            let c = m.query_advice(c, Rotation::cur());
            vec![s * (a_next - c)]
        });
        meta.lookup(|m| {
            let s = m.query_selector(s_lk);
            let b = m.query_advice(b, Rotation::cur());
            vec![(s * b, table)]
        });
        Cfg { a, b, c, inst, s_mul, s_chain, s_lk, table }
    }

    fn synthesize(&self, cfg: Cfg, mut layouter: impl Layouter<Fp>) -> Result<(), Error> {
        layouter.assign_table(
            || "range",
            |mut t| {
                for i in 0..8u64 {
                    t.assign_cell(|| "v", cfg.table, i as usize, || Value::known(Fp::from(i)))?;
                }
                Ok(())
            },
        )?;
        let out = layouter.assign_region(
            || "main",
            |mut r| {
                cfg.s_mul.enable(&mut r, 0)?;
                cfg.s_chain.enable(&mut r, 0)?;
                cfg.s_lk.enable(&mut r, 0)?;
                r.assign_advice(|| "a0", cfg.a, 0, || self.a0)?;
                r.assign_advice(|| "b0", cfg.b, 0, || self.b0)?;
                let c0 = r.assign_advice(|| "c0", cfg.c, 0, || self.a0 * self.b0)?;
                cfg.s_mul.enable(&mut r, 1)?;
                cfg.s_lk.enable(&mut r, 1)?;
                let a1 = c0.copy_advice(|| "a1", &mut r, cfg.a, 1)?;
                r.assign_advice(|| "b1", cfg.b, 1, || self.b1)?;
                let c1 = r.assign_advice(|| "c1", cfg.c, 1, || a1.value().copied() * self.b1)?;
                Ok(c1.cell())
            },
        )?;
        layouter.constrain_instance(out, cfg.inst, 0)
    }
}

fn main() {
    fs::create_dir_all("out").unwrap();
    let params: Params<vesta::Affine> = Params::new(K);
    let vk = keygen_vk(&params, &Toy::default()).unwrap();
    let pk = keygen_pk(&params, vk.clone(), &Toy::default()).unwrap();

    let circuits = [
        Toy { a0: Value::known(Fp::from(3)), b0: Value::known(Fp::from(5)), b1: Value::known(Fp::from(2)) },
        Toy { a0: Value::known(Fp::from(7)), b0: Value::known(Fp::from(4)), b1: Value::known(Fp::from(6)) },
    ];
    let outs = [Fp::from(30), Fp::from(168)];
    let inst0 = [outs[0]];
    let inst1 = [outs[1]];
    let instances: [&[&[Fp]]; 2] = [&[&inst0], &[&inst1]];

    let mut tw = Blake2bWrite::<_, vesta::Affine, Challenge255<_>>::init(vec![]);
    create_proof(&params, &pk, &circuits, &instances, StdRng::seed_from_u64(42), &mut tw).unwrap();
    let proof = tw.finalize();
    zebend_trace::take();

    let verify = |proof: &[u8]| -> (bool, Vec<(String, String)>) {
        let mut tr = Blake2bRead::<_, vesta::Affine, Challenge255<_>>::init(proof);
        let ok = verify_proof(&params, &vk, SingleVerifier::new(&params), &instances, &mut tr).is_ok();
        (ok, zebend_trace::take())
    };
    let (ok, trace) = verify(&proof);
    assert!(ok, "halo2 rejects its own proof");
    let mut txt = String::new();
    for (n, h) in &trace {
        txt += &format!("{n} {h}\n");
    }
    txt += "result 1\n";
    fs::write("out/toy_trace.txt", txt).unwrap();

    // a tampered proof: flip a bit in the last scalar (f)
    let mut bad = proof.clone();
    let at = bad.len() - 32;
    bad[at] ^= 1;
    let (bad_ok, _) = verify(&bad);
    assert!(!bad_ok, "halo2 accepts a tampered proof");

    fs::write("../toy_v.bend", bend_verifier(&params, &vk, 2, &[1], 3)).unwrap();
    let main_of = |proof: &[u8]| -> String {
        let items: Vec<String> = proof.chunks(32).map(item_lit).collect();
        let ivals: Vec<String> = outs.iter().map(|v| fp_lit(*v)).collect();
        format!(
            "import Base\nimport ../lib/words.bend as Wd\nimport ../lib/fp.bend as Fp\nimport ./vlib.bend as L\nimport ./toy_v.bend as T\n\n\
             def PROOF() -> L.Proof:\n  L.Proof{{[{}], [{}]}}\n\n\
             def main() -> IO(Unit):\n  +st = T.verify(PROOF())\n  do IO<Unit>:\n    L.print_log(L.st_log(st))\n    IO.print(\"result \" ++ U32.show(L.st_ok(st)))\n",
            items.join(",\n    "),
            ivals.join(", ")
        )
    };
    fs::write("../toy_main.bend", main_of(&proof)).unwrap();
    fs::write("../toy_bad_main.bend", main_of(&bad)).unwrap();
    println!("proof {} bytes, {} trace records; halo2: honest ok, tampered rejected", proof.len(), trace.len());
}
