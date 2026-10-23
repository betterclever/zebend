//! ORACLE PATCH: exports the parameters / verifying key and generates a Bend
//! description of the constraint system, for an independent Bend verifier.
//!
//! Every gate polynomial and lookup expression is lowered to one SSA program
//! (`Prog`). The same `Prog` is (a) printed as Bend and (b) evaluated here in Rust
//! over the evaluations recorded during a real verification, and compared with the
//! values halo2 itself computed. So the generated Bend is a mechanical printing of
//! IR that is checked against the official verifier.

use std::collections::BTreeSet;
use std::fmt::Write as _;

use ff::{Field, PrimeField, WithSmallOrderMulGroup};
use group::GroupEncoding;
use pasta_curves::{vesta, Fp};

use super::{circuit::Any, Expression, VerifyingKey};
use crate::poly::commitment::Params;

/// One SSA instruction; operands refer to earlier instruction indices.
#[derive(Clone, Debug)]
enum Op {
    Const(Fp),
    Fixed(usize),
    Advice(usize),
    Instance(usize),
    Neg(usize),
    Add(usize, usize),
    Mul(usize, usize),
}

#[derive(Default, Clone, Debug)]
struct Prog {
    ops: Vec<Op>,
}

impl Prog {
    fn push(&mut self, op: Op) -> usize {
        self.ops.push(op);
        self.ops.len() - 1
    }

    fn lower(&mut self, e: &Expression<Fp>) -> usize {
        match e {
            Expression::Constant(c) => self.push(Op::Const(*c)),
            Expression::Selector(_) => panic!("virtual selectors are removed during optimization"),
            Expression::Fixed(q) => self.push(Op::Fixed(q.index)),
            Expression::Advice(q) => self.push(Op::Advice(q.index)),
            Expression::Instance(q) => self.push(Op::Instance(q.index)),
            Expression::Negated(a) => {
                let a = self.lower(a);
                self.push(Op::Neg(a))
            }
            Expression::Sum(a, b) => {
                let a = self.lower(a);
                let b = self.lower(b);
                self.push(Op::Add(a, b))
            }
            Expression::Product(a, b) => {
                let a = self.lower(a);
                let b = self.lower(b);
                self.push(Op::Mul(a, b))
            }
            Expression::Scaled(a, s) => {
                let a = self.lower(a);
                let s = self.push(Op::Const(*s));
                self.push(Op::Mul(a, s))
            }
        }
    }

    fn of(e: &Expression<Fp>) -> Self {
        let mut p = Prog::default();
        p.lower(e);
        p
    }

    fn eval(&self, adv: &[Fp], fix: &[Fp], ins: &[Fp]) -> Fp {
        let mut v: Vec<Fp> = Vec::with_capacity(self.ops.len());
        for op in &self.ops {
            let x = match *op {
                Op::Const(c) => c,
                Op::Fixed(i) => fix[i],
                Op::Advice(i) => adv[i],
                Op::Instance(i) => ins[i],
                Op::Neg(a) => -v[a],
                Op::Add(a, b) => v[a] + v[b],
                Op::Mul(a, b) => v[a] * v[b],
            };
            v.push(x);
        }
        *v.last().unwrap()
    }

    /// Prints the program as one Bend def over the queried-evaluation lists.
    fn bend(&self, name: &str, out: &mut String) {
        writeln!(out, "def {name}(+a: +List<Z.F>, +f: +List<Z.F>, +i: +List<Z.F>) -> Z.F:").unwrap();
        let last = self.ops.len() - 1;
        for (k, op) in self.ops.iter().enumerate() {
            let rhs = match *op {
                Op::Const(c) => bend_const(c),
                Op::Fixed(j) => format!("at({j}n, f)"),
                Op::Advice(j) => format!("at({j}n, a)"),
                Op::Instance(j) => format!("at({j}n, i)"),
                Op::Neg(x) => format!("Z.fsub(Z.FZERO(), v{x})"),
                Op::Add(x, y) => format!("Z.fadd(v{x}, v{y})"),
                Op::Mul(x, y) => format!("Z.fmul(v{x}, v{y})"),
            };
            if k == last {
                writeln!(out, "  {rhs}").unwrap();
            } else {
                writeln!(out, "  +v{k} = {rhs}").unwrap();
            }
        }
        out.push('\n');
    }
}

/// `x` in zcrypto.bend's representation: Montgomery form (x·2^256 mod p), 16 limbs × 16 bits.
fn mont_limbs(x: Fp) -> [u32; 16] {
    let r = Fp::from(2u64).pow_vartime([256]);
    let m = (x * r).to_repr();
    let mut l = [0u32; 16];
    for (k, limb) in l.iter_mut().enumerate() {
        *limb = u16::from_le_bytes([m[2 * k], m[2 * k + 1]]) as u32;
    }
    l
}

fn bend_const(x: Fp) -> String {
    let l = mont_limbs(x);
    let parts: Vec<String> = l.iter().map(|v| v.to_string()).collect();
    format!("{{Z.F{{{}}} : Z.F}}", parts.join(", "))
}

fn hexs<F: PrimeField>(x: &F) -> String {
    hex::encode(x.to_repr().as_ref())
}

fn u32hex(v: usize) -> String {
    hex::encode((v as u32).to_le_bytes())
}

fn kind(c: &Any) -> usize {
    match c {
        Any::Advice => 0,
        Any::Fixed => 1,
        Any::Instance => 2,
    }
}

fn gate_progs(vk: &VerifyingKey<vesta::Affine>) -> Vec<(usize, usize, Prog)> {
    let mut v = vec![];
    for (gi, gate) in vk.cs.gates.iter().enumerate() {
        for (qi, poly) in gate.polynomials().iter().enumerate() {
            v.push((gi, qi, Prog::of(poly)));
        }
    }
    v
}

/// `name hex` text plus raw `g` / `g_lagrange` tables (32-byte compressed Vesta points).
pub fn export_params_vk(params: &Params<vesta::Affine>, vk: &VerifyingKey<vesta::Affine>) -> (String, Vec<u8>, Vec<u8>) {
    let mut t = String::new();
    let cs = &vk.cs;
    let mut line = |k: String, v: String| {
        t.push_str(&k);
        t.push(' ');
        t.push_str(&v);
        t.push('\n');
    };
    line("k".into(), u32hex(params.k as usize));
    line("n".into(), u32hex(params.n as usize));
    line("omega".into(), hexs(&vk.domain.get_omega()));
    line("omega_inv".into(), hexs(&vk.domain.get_omega_inv()));
    line("delta".into(), hexs(&<Fp as PrimeField>::DELTA));
    line("zeta".into(), hexs(&<Fp as WithSmallOrderMulGroup<3>>::ZETA));
    line("blinding_factors".into(), u32hex(cs.blinding_factors()));
    line("cs_degree".into(), u32hex(vk.cs_degree));
    line("quotient_poly_degree".into(), u32hex(vk.domain.get_quotient_poly_degree()));
    line("num_fixed_columns".into(), u32hex(cs.num_fixed_columns));
    line("num_advice_columns".into(), u32hex(cs.num_advice_columns));
    line("num_instance_columns".into(), u32hex(cs.num_instance_columns));
    line("transcript_repr".into(), hexs(&vk.transcript_repr));
    line("params.w".into(), hex::encode(params.w.to_bytes()));
    line("params.u".into(), hex::encode(params.u.to_bytes()));
    for (i, c) in vk.fixed_commitments.iter().enumerate() {
        line(format!("fixed_commitment[{i}]"), hex::encode(c.to_bytes()));
    }
    for (i, c) in vk.permutation.commitments.iter().enumerate() {
        line(format!("permutation_commitment[{i}]"), hex::encode(c.to_bytes()));
    }
    for (i, (col, rot)) in cs.advice_queries.iter().enumerate() {
        line(format!("advice_query[{i}]"), format!("{} {}", col.index(), rot.0));
    }
    for (i, (col, rot)) in cs.fixed_queries.iter().enumerate() {
        line(format!("fixed_query[{i}]"), format!("{} {}", col.index(), rot.0));
    }
    for (i, (col, rot)) in cs.instance_queries.iter().enumerate() {
        line(format!("instance_query[{i}]"), format!("{} {}", col.index(), rot.0));
    }
    for (i, col) in cs.permutation.get_columns().iter().enumerate() {
        line(
            format!("permutation_column[{i}]"),
            format!("{} {} {}", kind(col.column_type()), col.index(), cs.get_any_query_index(*col)),
        );
    }
    line("num_gates".into(), u32hex(cs.gates.len()));
    for (gi, gate) in cs.gates.iter().enumerate() {
        line(format!("gate[{gi}].num_polys"), u32hex(gate.polynomials().len()));
    }
    line("num_lookups".into(), u32hex(cs.lookups.len()));
    for (li, l) in cs.lookups.iter().enumerate() {
        line(format!("lookup[{li}].num_inputs"), u32hex(l.input_expressions.len()));
        line(format!("lookup[{li}].num_tables"), u32hex(l.table_expressions.len()));
    }
    let g: Vec<u8> = params.g.iter().flat_map(|p| p.to_bytes()).collect();
    let gl: Vec<u8> = params.g_lagrange.iter().flat_map(|p| p.to_bytes()).collect();
    (t, g, gl)
}

/// The Bend description of the constraint system (imports gpu-scan/zcrypto.bend as Z).
pub fn codegen_bend(vk: &VerifyingKey<vesta::Affine>) -> String {
    let cs = &vk.cs;
    let mut o = String::new();
    o.push_str(
        "# GENERATED by bend-zcash/halo2/oracle (oracle_export.rs) from the Orchard\n\
         # post-NU6.3 VerifyingKey (orchard 0.16, halo2_proofs 0.4). Do not edit.\n\
         #\n\
         # Field: Z.F is the Orchard circuit field Fp (pallas::Base = vesta::Scalar),\n\
         # in zcrypto.bend's Montgomery form (16 limbs x 16 bits). Constants below are\n\
         # already in Montgomery form.\n\
         #\n\
         # Evaluation lists: a = advice evals, f = fixed evals, i = instance evals, each in\n\
         # the exact order halo2's verifier reads them from the transcript (query order).\n\
         # Signed rotations are encoded as U32 two's complement.\n\
         import Base\n\
         import ../../gpu-scan/zcrypto.bend as Z\n\n",
    );
    o.push_str(
        "def at(n: Nat, +xs: +List<Z.F>) -> Z.F:\n  match n xs:\n    case 0n Con{h, _}:\n      h\n    case 0n Nil{}:\n      Z.FZERO()\n    case 1n+p Con{_, t}:\n      at(p, t)\n    case 1n+p Nil{}:\n      Z.FZERO()\n\n",
    );
    let nat = |n: usize| format!("{n}n");
    let mut meta = |name: &str, ty: &str, val: String| {
        writeln!(o, "def {name}() -> {ty}:\n  {val}\n").unwrap();
    };
    meta("K", "Nat", nat(vk.domain.oracle_k() as usize));
    meta("BLINDING_FACTORS", "Nat", nat(cs.blinding_factors()));
    meta("CS_DEGREE", "Nat", nat(vk.cs_degree));
    meta("QUOTIENT_POLY_DEGREE", "Nat", nat(vk.domain.get_quotient_poly_degree()));
    meta("NUM_ADVICE_COLUMNS", "Nat", nat(cs.num_advice_columns));
    meta("NUM_FIXED_COLUMNS", "Nat", nat(cs.num_fixed_columns));
    meta("NUM_INSTANCE_COLUMNS", "Nat", nat(cs.num_instance_columns));
    meta("NUM_ADVICE_QUERIES", "Nat", nat(cs.advice_queries.len()));
    meta("NUM_FIXED_QUERIES", "Nat", nat(cs.fixed_queries.len()));
    meta("NUM_INSTANCE_QUERIES", "Nat", nat(cs.instance_queries.len()));
    meta("NUM_PERMUTATION_COLUMNS", "Nat", nat(cs.permutation.get_columns().len()));
    meta("NUM_LOOKUPS", "Nat", nat(cs.lookups.len()));
    meta("OMEGA", "Z.F", bend_const(vk.domain.get_omega()));
    meta("OMEGA_INV", "Z.F", bend_const(vk.domain.get_omega_inv()));
    meta("DELTA", "Z.F", bend_const(<Fp as PrimeField>::DELTA));
    meta("TRANSCRIPT_REPR", "Z.F", bend_const(vk.transcript_repr));

    let rot = |r: i32| format!("{}", r as u32);
    let list_u32 = |xs: Vec<String>| format!("[{}]", xs.join(", "));
    meta(
        "ADVICE_QUERY_COLUMN",
        "+List<U32>",
        list_u32(cs.advice_queries.iter().map(|(c, _)| c.index().to_string()).collect()),
    );
    meta("ADVICE_QUERY_ROTATION", "+List<U32>", list_u32(cs.advice_queries.iter().map(|(_, r)| rot(r.0)).collect()));
    meta("FIXED_QUERY_COLUMN", "+List<U32>", list_u32(cs.fixed_queries.iter().map(|(c, _)| c.index().to_string()).collect()));
    meta("FIXED_QUERY_ROTATION", "+List<U32>", list_u32(cs.fixed_queries.iter().map(|(_, r)| rot(r.0)).collect()));
    meta(
        "INSTANCE_QUERY_COLUMN",
        "+List<U32>",
        list_u32(cs.instance_queries.iter().map(|(c, _)| c.index().to_string()).collect()),
    );
    meta("INSTANCE_QUERY_ROTATION", "+List<U32>", list_u32(cs.instance_queries.iter().map(|(_, r)| rot(r.0)).collect()));
    let pcols = cs.permutation.get_columns();
    meta("PERMUTATION_COLUMN_KIND", "+List<U32>", list_u32(pcols.iter().map(|c| kind(c.column_type()).to_string()).collect()));
    meta(
        "PERMUTATION_COLUMN_QUERY_INDEX",
        "+List<U32>",
        list_u32(pcols.iter().map(|c| cs.get_any_query_index(*c).to_string()).collect()),
    );

    // Distinct rotations and omega^rotation, so rotated points are x * ROT_FACTOR.
    let mut rots: BTreeSet<i32> = BTreeSet::new();
    for (_, r) in cs.advice_queries.iter() {
        rots.insert(r.0);
    }
    for (_, r) in cs.fixed_queries.iter() {
        rots.insert(r.0);
    }
    for (_, r) in cs.instance_queries.iter() {
        rots.insert(r.0);
    }
    rots.insert(1);
    rots.insert(-1);
    rots.insert(-((cs.blinding_factors() + 1) as i32));
    for r in &rots {
        let f = vk.domain.rotate_omega(Fp::ONE, crate::poly::Rotation(*r));
        let name = if *r < 0 { format!("ROT_FACTOR_M{}", -r) } else { format!("ROT_FACTOR_{r}") };
        meta(&name, "Z.F", bend_const(f));
    }

    // Gates.
    let gates = gate_progs(vk);
    let mut names = vec![];
    for (gi, qi, p) in &gates {
        let name = format!("gate_{gi}_{qi}");
        p.bend(&name, &mut o);
        names.push(name);
    }
    // gate_polys: all gate polynomial values, in halo2's order, built as a cons chain.
    o.push_str("def gate_polys(+a: +List<Z.F>, +f: +List<Z.F>, +i: +List<Z.F>) -> +List<Z.F>:\n");
    let mut chain = String::from("[]");
    for n in names.iter().rev() {
        chain = format!("{n}(a, f, i) <> {chain}");
    }
    let _ = writeln!(o, "  {chain}\n");

    // Lookups: input and table expressions, each its own def, plus list builders.
    for (li, l) in cs.lookups.iter().enumerate() {
        for (side, exprs) in [("input", &l.input_expressions), ("table", &l.table_expressions)] {
            let mut ns = vec![];
            for (ei, e) in exprs.iter().enumerate() {
                let name = format!("lookup_{li}_{side}_{ei}");
                Prog::of(e).bend(&name, &mut o);
                ns.push(name);
            }
            let _ = writeln!(o, "def lookup_{li}_{side}s(+a: +List<Z.F>, +f: +List<Z.F>, +i: +List<Z.F>) -> +List<Z.F>:");
            let mut chain = String::from("[]");
            for n in ns.iter().rev() {
                chain = format!("{n}(a, f, i) <> {chain}");
            }
            let _ = writeln!(o, "  {chain}\n");
        }
    }
    o
}

/// Re-evaluates every gate polynomial (and each lookup's theta-compressed input/table)
/// through the IR over the evaluations recorded in `log`, and asserts equality with the
/// values halo2 computed. Returns the number of values checked.
pub fn check_codegen_against_dump(vk: &VerifyingKey<vesta::Affine>, log: &[(String, Vec<u8>)]) -> usize {
    let cs = &vk.cs;
    let fp = |b: &[u8]| -> Fp {
        let mut r = [0u8; 32];
        r.copy_from_slice(b);
        Fp::from_repr(r).unwrap()
    };
    // Split the transcript scalars by phase.
    let mut phase = String::new();
    let mut inst: Vec<Fp> = vec![];
    let mut adv: Vec<Fp> = vec![];
    let mut fix: Vec<Fp> = vec![];
    let mut theta = Fp::ZERO;
    let (mut beta, mut gamma, mut l_last, mut l_blind) = (Fp::ZERO, Fp::ZERO, Fp::ZERO, Fp::ZERO);
    let mut lookup_evals: Vec<Fp> = vec![];
    let mut expected: Vec<(String, Fp)> = vec![];
    for (name, bytes) in log {
        match name.as_str() {
            "phase" => phase = String::from_utf8_lossy(bytes).into_owned(),
            "theta" => theta = fp(bytes),
            "beta" => beta = fp(bytes),
            "gamma" => gamma = fp(bytes),
            "l_last" => l_last = fp(bytes),
            "l_blind" => l_blind = fp(bytes),
            "tx.absorb_scalar" if phase == "lookup_evals" => lookup_evals.push(fp(bytes)),
            "tx.absorb_scalar" if phase == "instance_evals" => inst.push(fp(bytes)),
            "tx.absorb_scalar" if phase == "advice_evals" => adv.push(fp(bytes)),
            "tx.absorb_scalar" if phase == "fixed_evals" => fix.push(fp(bytes)),
            n if n.starts_with("expr[") => expected.push((n.to_string(), fp(bytes))),
            _ => {}
        }
    }
    let num_proofs = inst.len() / cs.instance_queries.len().max(1);
    let (ni, na) = (cs.instance_queries.len(), cs.advice_queries.len());
    let progs = gate_progs(vk);
    let mut checked = 0;
    for pi in 0..num_proofs {
        let ins = &inst[pi * ni..(pi + 1) * ni];
        let ad = &adv[pi * na..(pi + 1) * na];
        for (gi, qi, p) in &progs {
            let label = format!("expr[{pi}].gate[{gi}].poly[{qi}]");
            let want = expected.iter().find(|(n, _)| *n == label).unwrap_or_else(|| panic!("missing {label}")).1;
            assert_eq!(p.eval(ad, &fix, ins), want, "codegen mismatch at {label}");
            checked += 1;
        }
        // Lookups: rebuild halo2's product term from the IR's compressed input/table
        // expressions and the transcript evals, and compare with halo2's own term.
        let nl = cs.lookups.len();
        for (li, l) in cs.lookups.iter().enumerate() {
            let compress = |es: &[Expression<Fp>]| {
                es.iter().map(|e| Prog::of(e).eval(ad, &fix, ins)).fold(Fp::ZERO, |acc, v| acc * theta + v)
            };
            let base = (pi * nl + li) * 5;
            let (prod, prod_next, pin, _pin_inv, ptab) =
                (lookup_evals[base], lookup_evals[base + 1], lookup_evals[base + 2], lookup_evals[base + 3], lookup_evals[base + 4]);
            let active = Fp::ONE - (l_last + l_blind);
            let left = prod_next * (pin + beta) * (ptab + gamma);
            let right = prod * (compress(&l.input_expressions) + beta) * (compress(&l.table_expressions) + gamma);
            let term = (left - right) * active;
            let label = format!("expr[{pi}].lookup_term[{}]", li * 5 + 2);
            let want = expected.iter().find(|(n, _)| *n == label).unwrap_or_else(|| panic!("missing {label}")).1;
            assert_eq!(term, want, "lookup codegen mismatch at {label}");
            checked += 1;
        }
    }
    checked
}

fn bend_list(xs: &[Fp]) -> String {
    let mut chain = String::from("[]");
    for x in xs.iter().rev() {
        chain = format!("{} <> {chain}", bend_const(*x));
    }
    chain
}

/// A Bend program that evaluates the generated gates and lookup expressions on the
/// evaluations recorded for proof `pi`, and counts matches with halo2's values.
pub fn bend_selftest(vk: &VerifyingKey<vesta::Affine>, log: &[(String, Vec<u8>)], pi: usize) -> String {
    let cs = &vk.cs;
    let fp = |b: &[u8]| -> Fp {
        let mut r = [0u8; 32];
        r.copy_from_slice(b);
        Fp::from_repr(r).unwrap()
    };
    let mut phase = String::new();
    let (mut inst, mut adv, mut fix) = (vec![], vec![], vec![]);
    let mut gates_want = vec![];
    for (name, bytes) in log {
        match name.as_str() {
            "phase" => phase = String::from_utf8_lossy(bytes).into_owned(),
            "tx.absorb_scalar" if phase == "instance_evals" => inst.push(fp(bytes)),
            "tx.absorb_scalar" if phase == "advice_evals" => adv.push(fp(bytes)),
            "tx.absorb_scalar" if phase == "fixed_evals" => fix.push(fp(bytes)),
            n if n.starts_with(&format!("expr[{pi}].gate[")) => gates_want.push(fp(bytes)),
            _ => {}
        }
    }
    let (ni, na) = (cs.instance_queries.len(), cs.advice_queries.len());
    let ins = &inst[pi * ni..(pi + 1) * ni];
    let ad = &adv[pi * na..(pi + 1) * na];
    let mut o = String::new();
    o.push_str("# GENERATED self-test: generated gates in Bend vs halo2's recorded values.\nimport Base\nimport ../../gpu-scan/zcrypto.bend as Z\nimport ./orchard_cs.bend as C\n\n");
    let _ = writeln!(o, "def A() -> +List<Z.F>:\n  {}\n", bend_list(ad));
    let _ = writeln!(o, "def FX() -> +List<Z.F>:\n  {}\n", bend_list(&fix));
    let _ = writeln!(o, "def I() -> +List<Z.F>:\n  {}\n", bend_list(ins));
    let _ = writeln!(o, "def WANT() -> +List<Z.F>:\n  {}\n", bend_list(&gates_want));
    o.push_str("def count(+xs: +List<Z.F>, +ys: +List<Z.F>) -> U32:\n  match xs ys:\n    case Con{x, xt} Con{y, yt}:\n      (Z.fis_eq(x, y) + count(xt, yt) : U32)\n    case _ _:\n      0\n\n");
    o.push_str("def main() -> IO(Unit):\n  do IO<Unit>:\n    +got : +List<Z.F> = C.gate_polys(A(), FX(), I())\n    IO.print(\"gate polys matching halo2: \" ++ U32.show(count(got, WANT())) ++ \" / \" ++ U32.show(U32.from_nat(List.length(&2, Z.F, WANT()))))\n");
    o
}
