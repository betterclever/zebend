//! A small Halo 2 circuit with every argument the Orchard verifier uses (a custom
//! gate, a lookup, the permutation argument and an instance column), so the Bend
//! verifier can iterate on a proof that is ~10x smaller than Orchard's.
//!
//! Statement: c = a·b with a ∈ [0, 8) (lookup), and c equals the public input.

use halo2_proofs::{
    circuit::{Layouter, SimpleFloorPlanner, Value},
    plonk::{
        create_proof, keygen_pk, keygen_vk, verify_proof, Advice, Circuit, Column, ConstraintSystem, Error,
        Instance, Selector, SingleVerifier, TableColumn, VerifyingKey,
    },
    poly::{commitment::Params, Rotation},
    transcript::{Blake2bRead, Blake2bWrite, Challenge255},
};
use pasta_curves::{vesta, Fp};
use rand::{rngs::StdRng, SeedableRng};

pub const K: u32 = 5;

#[derive(Clone, Debug)]
pub struct ToyConfig {
    a: Column<Advice>,
    b: Column<Advice>,
    c: Column<Advice>,
    instance: Column<Instance>,
    s_mul: Selector,
    s_range: Selector,
    table: TableColumn,
}

#[derive(Default, Clone)]
pub struct Toy {
    pub a: Value<Fp>,
    pub b: Value<Fp>,
}

impl Circuit<Fp> for Toy {
    type Config = ToyConfig;
    type FloorPlanner = SimpleFloorPlanner;

    fn without_witnesses(&self) -> Self {
        Self::default()
    }

    fn configure(meta: &mut ConstraintSystem<Fp>) -> ToyConfig {
        let a = meta.advice_column();
        let b = meta.advice_column();
        let c = meta.advice_column();
        let instance = meta.instance_column();
        meta.enable_equality(c);
        meta.enable_equality(instance);
        let s_mul = meta.selector();
        let s_range = meta.complex_selector();
        let table = meta.lookup_table_column();

        meta.create_gate("mul", |m| {
            let s = m.query_selector(s_mul);
            let a = m.query_advice(a, Rotation::cur());
            let b = m.query_advice(b, Rotation::cur());
            let c = m.query_advice(c, Rotation::cur());
            vec![s * (a * b - c)]
        });
        meta.lookup(|m| {
            let s = m.query_selector(s_range);
            let a = m.query_advice(a, Rotation::cur());
            vec![(s * a, table)]
        });
        ToyConfig { a, b, c, instance, s_mul, s_range, table }
    }

    fn synthesize(&self, cfg: ToyConfig, mut layouter: impl Layouter<Fp>) -> Result<(), Error> {
        layouter.assign_table(
            || "range 0..8",
            |mut t| {
                for i in 0..8u64 {
                    t.assign_cell(|| "v", cfg.table, i as usize, || Value::known(Fp::from(i)))?;
                }
                Ok(())
            },
        )?;
        let c = layouter.assign_region(
            || "mul",
            |mut r| {
                cfg.s_mul.enable(&mut r, 0)?;
                cfg.s_range.enable(&mut r, 0)?;
                r.assign_advice(|| "a", cfg.a, 0, || self.a)?;
                r.assign_advice(|| "b", cfg.b, 0, || self.b)?;
                r.assign_advice(|| "c", cfg.c, 0, || self.a * self.b)
            },
        )?;
        layouter.constrain_instance(c.cell(), cfg.instance, 0)
    }
}

/// Returns (params, vk, proof bytes, public input).
pub fn prove() -> (Params<vesta::Affine>, VerifyingKey<vesta::Affine>, Vec<u8>, Vec<Fp>) {
    let params = Params::<vesta::Affine>::new(K);
    let empty = Toy::default();
    let vk = keygen_vk(&params, &empty).unwrap();
    let pk = keygen_pk(&params, vk.clone(), &empty).unwrap();
    let circuit = Toy { a: Value::known(Fp::from(5)), b: Value::known(Fp::from(7)) };
    let public = vec![Fp::from(35)];
    let mut transcript = Blake2bWrite::<_, vesta::Affine, Challenge255<_>>::init(vec![]);
    create_proof(&params, &pk, &[circuit], &[&[&public]], StdRng::seed_from_u64(5), &mut transcript).unwrap();
    (params, vk, transcript.finalize(), public)
}

pub fn verify(params: &Params<vesta::Affine>, vk: &VerifyingKey<vesta::Affine>, proof: &[u8], public: &[Fp]) -> Result<(), Error> {
    let mut t = Blake2bRead::<_, vesta::Affine, Challenge255<_>>::init(proof);
    verify_proof(params, vk, SingleVerifier::new(params), &[&[public]], &mut t)
}
