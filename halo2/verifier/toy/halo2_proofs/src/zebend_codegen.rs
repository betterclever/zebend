//! Zebend: emits a straight-line Bend verifier for one halo2 `VerifyingKey` over Vesta.
//!
//! The verifier's control flow (what is read from the transcript and in which order, which
//! queries exist, how multiopen groups them, and which MSM terms appear) depends only on the
//! verifying key, never on the proof. So we walk `verify_proof` symbolically here and emit Bend
//! that performs exactly the same field operations on the actual proof values. Every step
//! mirrors a line of plonk/verifier.rs, vanishing/verifier.rs, permutation/verifier.rs,
//! lookup/verifier.rs, poly/multiopen{.rs,/verifier.rs} and poly/commitment/verifier.rs.
//!
//! Runtime pieces (field ops, transcript, point reading) live in halo2-bend/verifier/vtail.bend,
//! imported as `L`.

use std::collections::{BTreeSet, HashMap};

use group::ff::{Field, PrimeField};
use indexmap::IndexMap;
use pasta_curves::{arithmetic::CurveAffine, vesta, Fp};

use crate::plonk::{Any, Expression, VerifyingKey};
use crate::poly::{commitment::Params, Rotation};

/// Montgomery limbs (R = 2^256, 16 × 16 bits) of an Fp element, as zc.bend stores it.
fn mont_limbs(v: Fp) -> [u32; 16] {
    let r = Fp::from(2).pow_vartime([256u64]);
    let bytes = (v * r).to_repr();
    let mut out = [0u32; 16];
    for (i, o) in out.iter_mut().enumerate() {
        *o = u16::from_le_bytes([bytes[2 * i], bytes[2 * i + 1]]) as u32;
    }
    out
}

fn words_lit(bytes: &[u8]) -> String {
    let ws: Vec<String> = (0..8)
        .map(|i| u32::from_le_bytes(bytes[4 * i..4 * i + 4].try_into().unwrap()).to_string())
        .collect();
    format!("Wd.W{{{}}}", ws.join(", "))
}

/// A Vesta point as a Bend `V.Pt` expression (from canonical affine Fq coordinates).
pub fn point_lit(p: &vesta::Affine) -> String {
    let c = p.coordinates().unwrap();
    format!(
        "V.from_aff(V.Aff{{Fq.from_words({}), Fq.from_words({})}})",
        words_lit(c.x().to_repr().as_ref()),
        words_lit(c.y().to_repr().as_ref())
    )
}

/// Raw 32 bytes as a Bend `Wd.W` literal.
pub fn item_lit(bytes: &[u8]) -> String {
    words_lit(bytes)
}

/// An Fp element as a Bend `Fp.Fp` literal (Montgomery limbs).
pub fn fp_lit(v: Fp) -> String {
    let limbs = mont_limbs(v);
    format!("Fp.Fp{{{}}}", limbs.iter().map(|x| x.to_string()).collect::<Vec<_>>().join(", "))
}

/// Commitment identity (halo2 groups multiopen queries by commitment *reference*).
/// Per-proof commitments carry the proof index.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
enum Key {
    Inst(usize, usize),
    Adv(usize, usize),
    PermProd(usize, usize),
    LkProd(usize, usize),
    LkIn(usize, usize),
    LkTab(usize, usize),
    Fixed(usize),
    PermCommon(usize),
    H,
    Rand,
}

/// A symbolic MSM: (scalar variable, point expression) terms.
#[derive(Clone, Default)]
struct Msm(Vec<(String, String)>);

struct Gen {
    lines: Vec<String>,
    /// Bend type of every bound variable (needed to pass live ones across def boundaries).
    types: HashMap<String, String>,
    n: usize,
    st: usize,
    consts: HashMap<[u32; 16], String>,
    const_defs: Vec<String>,
    one: String,
    zero: String,
}

impl Gen {
    fn new() -> Self {
        let mut g = Gen {
            lines: vec![],
            types: HashMap::new(),
            n: 0,
            st: 0,
            consts: HashMap::new(),
            const_defs: vec![],
            one: String::new(),
            zero: String::new(),
        };
        g.one = g.konst(Fp::ONE);
        g.zero = g.konst(Fp::ZERO);
        g
    }
    fn fresh(&mut self, base: &str) -> String {
        self.n += 1;
        format!("{base}{}", self.n)
    }
    fn bind(&mut self, expr: String) -> String {
        self.bind_t(expr, "Fp.Fp")
    }
    fn bind_t(&mut self, expr: String, ty: &str) -> String {
        let v = self.fresh("t");
        self.lines.push(format!("  +{v} = {expr}"));
        self.types.insert(v.clone(), ty.to_string());
        v
    }
    fn bind_as(&mut self, v: &str, expr: String, ty: &str) {
        self.lines.push(format!("  +{v} = {expr}"));
        self.types.insert(v.to_string(), ty.to_string());
    }
    /// A constant field element as a zero-argument def (keeps `verify` short).
    fn konst(&mut self, v: Fp) -> String {
        let limbs = mont_limbs(v);
        if let Some(name) = self.consts.get(&limbs) {
            return format!("{name}()");
        }
        let name = format!("K{}", self.consts.len());
        let lit = limbs.iter().map(|x| x.to_string()).collect::<Vec<_>>().join(", ");
        self.const_defs.push(format!("def {name}() -> Fp.Fp:\n  Fp.Fp{{{lit}}}\n"));
        self.consts.insert(limbs, name.clone());
        format!("{name}()")
    }
    fn mul(&mut self, a: &str, b: &str) -> String {
        self.bind(format!("Fp.mul({a}, {b})"))
    }
    fn add(&mut self, a: &str, b: &str) -> String {
        self.bind(format!("Fp.add({a}, {b})"))
    }
    fn sub(&mut self, a: &str, b: &str) -> String {
        self.bind(format!("Fp.sub({a}, {b})"))
    }
    fn neg(&mut self, a: &str) -> String {
        self.bind(format!("Fp.neg({a})"))
    }
    fn inv(&mut self, a: &str) -> String {
        self.bind(format!("Fp.inv({a})"))
    }
    fn sq(&mut self, a: &str) -> String {
        self.mul(a, a)
    }
    fn st(&self) -> String {
        format!("st{}", self.st)
    }
    fn next_st(&mut self, expr: String) {
        let cur = self.st;
        self.st += 1;
        let _ = cur;
        let s = self.st();
        self.bind_as(&s, expr, "L.St");
    }
    fn log(&mut self, name: &str, v: &str) {
        let st = self.st();
        self.next_st(format!("L.lgf({st}, \"{name}\", {v})"));
    }
    fn check(&mut self, cond: &str) {
        let st = self.st();
        self.next_st(format!("L.check({st}, {cond})"));
    }
    fn squeeze(&mut self, name: &str) -> String {
        let st = self.st();
        let r = self.fresh("r");
        self.bind_as(&r, format!("L.squeeze({st})"), "L.SF");
        let v = self.bind(format!("L.sf_v({r})"));
        self.next_st(format!("L.sf_st({r})"));
        self.log(name, &v);
        v
    }
    fn rd_scalar(&mut self, name: &str) -> String {
        let st = self.st();
        let r = self.fresh("r");
        self.bind_as(&r, format!("L.rd_scalar({st})"), "L.SF");
        let v = self.bind(format!("L.sf_v({r})"));
        self.next_st(format!("L.sf_st({r})"));
        self.log(name, &v);
        v
    }
    fn rd_point(&mut self, name: &str) -> String {
        let st = self.st();
        let r = self.fresh("r");
        self.bind_as(&r, format!("L.rd_point({st})"), "L.SP");
        let p = self.fresh(&format!("p_{name}_"));
        self.bind_as(&p, format!("L.sp_p({r})"), "V.Pt");
        self.next_st(format!("L.sp_st({r})"));
        p
    }
    fn rd_ival(&mut self) -> String {
        let st = self.st();
        let r = self.fresh("r");
        self.bind_as(&r, format!("L.rd_ival({st})"), "L.SF");
        let v = self.bind(format!("L.sf_v({r})"));
        self.next_st(format!("L.sf_st({r})"));
        v
    }
    fn ab_point(&mut self, p: &str) {
        let st = self.st();
        self.next_st(format!("L.ab_point({st}, {p})"));
    }
    fn rd_scalars(&mut self, n: usize) -> String {
        let st = self.st();
        let r = self.fresh("r");
        self.bind_as(&r, format!("L.rd_scalars({st}, {n}n)"), "L.SL");
        let v = self.fresh("sl");
        self.bind_as(&v, format!("L.sl_v({r})"), "+List<Fp.Fp>");
        self.next_st(format!("L.sl_st({r})"));
        v
    }
    fn rd_points(&mut self, n: usize) -> String {
        let st = self.st();
        let r = self.fresh("r");
        self.bind_as(&r, format!("L.rd_points({st}, {n}n)"), "L.PL");
        let v = self.fresh("pl");
        self.bind_as(&v, format!("L.pl_v({r})"), "+List<V.Pt>");
        self.next_st(format!("L.pl_st({r})"));
        v
    }
    fn ms_empty(&mut self) -> String {
        self.bind_t("L.ms_empty()".into(), "L.MS")
    }
    fn ms_push(&mut self, m: &str, s: &str, p: &str) -> String {
        self.bind_t(format!("L.ms_push({m}, {s}, {p})"), "L.MS")
    }
    fn ms_scale(&mut self, m: &str, f: &str) -> String {
        self.bind_t(format!("L.ms_scale({m}, {f})"), "L.MS")
    }
    fn ms_cat(&mut self, a: &str, b: &str) -> String {
        self.bind_t(format!("L.ms_cat({a}, {b})"), "L.MS")
    }
    fn ab_scalar(&mut self, v: &str) {
        let st = self.st();
        self.next_st(format!("L.ab_scalar({st}, {v})"));
    }

    fn expr(&mut self, e: &Expression<Fp>, fixed: &[String], advice: &[String], inst: &[String]) -> String {
        match e {
            Expression::Constant(c) => self.konst(*c),
            Expression::Selector(_) => panic!("virtual selectors are removed during optimization"),
            Expression::Fixed(q) => fixed[q.index].clone(),
            Expression::Advice(q) => advice[q.index].clone(),
            Expression::Instance(q) => inst[q.index].clone(),
            Expression::Negated(a) => {
                let a = self.expr(a, fixed, advice, inst);
                self.neg(&a)
            }
            Expression::Sum(a, b) => {
                let a = self.expr(a, fixed, advice, inst);
                let b = self.expr(b, fixed, advice, inst);
                self.add(&a, &b)
            }
            Expression::Product(a, b) => {
                let a = self.expr(a, fixed, advice, inst);
                let b = self.expr(b, fixed, advice, inst);
                self.mul(&a, &b)
            }
            Expression::Scaled(a, c) => {
                let a = self.expr(a, fixed, advice, inst);
                let c = self.konst(*c);
                self.mul(&a, &c)
            }
        }
    }

    fn msm_scale(&mut self, m: &mut Msm, f: &str) {
        for t in m.0.iter_mut() {
            t.0 = self.mul(&t.0, f);
        }
    }
}

/// Splits the straight-line body into a chain of defs `verify`, `verify_1`, ... Bend's native
/// backend flattens a def's parameters into registers (an Fp is 16 words, a Vesta point 48,
/// a list 1) and caps them at 247, so live Fp and point values are *boxed* into one list each
/// when crossing a def boundary and read back by index inside the next def. Cuts happen only
/// where no read-result record (SF/SP/SL/PL) is live. Defs are emitted callee-first.
fn segment(lines: &[String], types: &HashMap<String, String>, result: &str, max_lines: usize) -> String {
    // identifiers outside string literals, with their byte spans
    fn tokens(l: &str) -> Vec<(usize, usize)> {
        let b = l.as_bytes();
        let mut out = vec![];
        let mut i = 0;
        let mut in_str = false;
        while i < b.len() {
            let c = b[i];
            if c == b'"' {
                in_str = !in_str;
                i += 1;
                continue;
            }
            if !in_str && (c.is_ascii_alphanumeric() || c == b'_' || c == b'.') {
                let st = i;
                while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_' || b[i] == b'.') {
                    i += 1;
                }
                out.push((st, i));
            } else {
                i += 1;
            }
        }
        out
    }
    let parsed: Vec<(String, Vec<String>)> = lines
        .iter()
        .map(|l| {
            let (lhs, rhs) = l.trim().trim_start_matches('+').split_once(" = ").unwrap();
            let used = tokens(rhs).into_iter().map(|(a, b)| rhs[a..b].to_string()).filter(|t| types.contains_key(t)).collect();
            (lhs.to_string(), used)
        })
        .collect();
    let n = parsed.len();
    // live_after[i]: variables used after line i (by later lines or the result), defined at or before i
    let mut live_after: Vec<BTreeSet<String>> = vec![BTreeSet::new(); n];
    let mut live: BTreeSet<String> = [result.to_string()].into_iter().collect();
    for i in (0..n).rev() {
        live_after[i] = live.clone();
        live.remove(&parsed[i].0);
        live.extend(parsed[i].1.iter().cloned());
    }
    let record = |v: &String| matches!(types[v].as_str(), "L.SF" | "L.SP" | "L.SL" | "L.PL");
    // cut after line i when the segment is long enough and no record is live
    let mut cuts = vec![];
    let mut start = 0;
    for i in 0..n.saturating_sub(1) {
        if i + 1 - start >= max_lines && !live_after[i].iter().any(record) {
            cuts.push(i + 1);
            start = i + 1;
        }
    }
    let mut bounds = vec![0];
    bounds.extend(cuts.iter().cloned());
    bounds.push(n);
    let boxed_f = |v: &String| types[v] == "Fp.Fp";
    let boxed_p = |v: &String| types[v] == "V.Pt";
    let mut defs = vec![];
    let nseg = bounds.len() - 1;
    for si in 0..nseg {
        let (a, b) = (bounds[si], bounds[si + 1]);
        let name = if si == 0 { "verify".to_string() } else { format!("verify_{si}") };
        let live_in: Vec<String> = if si == 0 { vec![] } else { live_after[a - 1].iter().cloned().collect() };
        let fin: Vec<&String> = live_in.iter().filter(|v| boxed_f(v)).collect();
        let pin: Vec<&String> = live_in.iter().filter(|v| boxed_p(v)).collect();
        let direct: Vec<&String> = live_in.iter().filter(|v| !boxed_f(v) && !boxed_p(v)).collect();
        let mut repl: HashMap<String, String> = HashMap::new();
        for (i, v) in fin.iter().enumerate() {
            repl.insert((*v).clone(), format!("L.fat({i}n, envf)"));
        }
        for (i, v) in pin.iter().enumerate() {
            repl.insert((*v).clone(), format!("L.pat({i}n, envp)"));
        }
        let params: Vec<String> = if si == 0 {
            vec!["pr: L.Proof".into()]
        } else {
            let mut ps = vec!["+envf: +List<Fp.Fp>".to_string(), "+envp: +List<V.Pt>".to_string()];
            ps.extend(direct.iter().map(|v| format!("+{v}: {}", types[*v])));
            ps
        };
        let rewrite = |l: &str| -> String {
            let mut out = String::new();
            let mut last = 0;
            for (x, y) in tokens(l) {
                if let Some(r) = repl.get(&l[x..y]) {
                    out.push_str(&l[last..x]);
                    out.push_str(r);
                    last = y;
                }
            }
            out.push_str(&l[last..]);
            out
        };
        let mut body = format!("def {name}({}) -> L.St:\n", params.join(", "));
        for l in &lines[a..b] {
            body.push_str(&rewrite(l));
            body.push('\n');
        }
        if si + 1 < nseg {
            let nxt: Vec<String> = live_after[b - 1].iter().cloned().collect();
            let f: Vec<String> = nxt.iter().filter(|v| boxed_f(v)).map(|v| rewrite(v)).collect();
            let pp: Vec<String> = nxt.iter().filter(|v| boxed_p(v)).map(|v| rewrite(v)).collect();
            let d: Vec<String> = nxt.iter().filter(|v| !boxed_f(v) && !boxed_p(v)).map(|v| rewrite(v)).collect();
            let mut args = vec![format!("[{}]", f.join(", ")), format!("[{}]", pp.join(", "))];
            args.extend(d);
            body.push_str(&format!("  verify_{}({})\n", si + 1, args.join(", ")));
        } else {
            body.push_str(&format!("  {}\n", rewrite(result)));
        }
        defs.push(body);
    }
    defs.reverse();
    defs.join("\n")
}

fn fat(list: &str, i: usize) -> String {
    format!("L.fat({i}n, {list})")
}

fn pat(list: &str, i: usize) -> String {
    format!("L.pat({i}n, {list})")
}

/// Emits a Bend module defining `verify(pr: L.Proof) -> L.St` for `num_proofs` circuit
/// instances sharing one transcript (as an Orchard bundle does), each instance column holding
/// `inst_len[c]` values. `msm_depth` sets the parallel MSM tree depth (2^depth leaves).
///
/// Values read from the proof live in runtime lists (accessed by index) and the MSM is a
/// runtime accumulator, so the generated `verify` keeps only a few dozen live variables
/// whatever the circuit size (Bend caps a def's live set at 247).
pub fn bend_verifier(
    params: &Params<vesta::Affine>,
    vk: &VerifyingKey<vesta::Affine>,
    num_proofs: usize,
    inst_len: &[usize],
    msm_depth: usize,
) -> String {
    let cs = &vk.cs;
    let dom = &vk.domain;
    let np = num_proofs;
    assert_eq!(inst_len.len(), cs.num_instance_columns);
    let mut g = Gen::new();
    let k = params.k;
    let omega = dom.omega;
    let omega_inv = dom.omega_inv;
    let rot_const = |r: i32| -> Fp {
        if r >= 0 {
            omega.pow_vartime([r as u64])
        } else {
            omega_inv.pow_vartime([(-(r as i64)) as u64])
        }
    };
    let mut point_defs = vec![];
    point_defs.push(format!("def PARAM_W() -> V.Pt:\n  {}\n", point_lit(&params.w)));
    point_defs.push(format!("def PARAM_U() -> V.Pt:\n  {}\n", point_lit(&params.u)));
    let max_len = inst_len.iter().cloned().max().unwrap_or(0);
    for j in 0..max_len {
        point_defs.push(format!("def G_LAG{j}() -> V.Pt:\n  {}\n", point_lit(&params.g_lagrange[j])));
    }
    let g_list: Vec<String> = params.g.iter().map(point_lit).collect();
    point_defs.push(format!("def G_ALL() -> +List<V.Pt>:\n  [{}]\n", g_list.join(",\n   ")));
    for (i, c) in vk.fixed_commitments.iter().enumerate() {
        point_defs.push(format!("def VK_FIXED{i}() -> V.Pt:\n  {}\n", point_lit(c)));
    }
    for (i, c) in vk.permutation.commitments.iter().enumerate() {
        point_defs.push(format!("def VK_PERM{i}() -> V.Pt:\n  {}\n", point_lit(c)));
    }

    // instance commitments: commit_lagrange(instance, Blind::default()) = sum inst_j G_lag_j + 1*W
    let mut insts: Vec<Vec<String>> = vec![];
    for _ in 0..np {
        let mut cols = vec![];
        for len in inst_len.iter() {
            let mut acc = "PARAM_W()".to_string();
            for j in 0..*len {
                let v = g.rd_ival();
                let t = g.bind_t(format!("V.scalar_mul_s(G_LAG{j}(), {v})"), "V.Pt");
                acc = g.bind_t(format!("V.add({acc}, {t})"), "V.Pt");
            }
            cols.push(acc);
        }
        insts.push(cols);
    }
    // vk.hash_into, then the instance commitments as common points
    let repr = g.konst(vk.transcript_repr);
    g.ab_scalar(&repr);
    for cols in &insts {
        for c in cols {
            g.ab_point(c);
        }
    }
    let nl = cs.lookups.len();
    let adv: Vec<String> = (0..np).map(|_| g.rd_points(cs.num_advice_columns)).collect();
    let theta = g.squeeze("theta");
    // per proof: [in0, tab0, in1, tab1, ...]
    let lk_perm: Vec<String> = (0..np).map(|_| g.rd_points(2 * nl)).collect();
    let beta = g.squeeze("beta");
    let gamma = g.squeeze("gamma");
    let chunk_len = vk.cs_degree - 2;
    let perm_chunks = cs.permutation.columns.chunks(chunk_len).count();
    let perm_prod: Vec<String> = (0..np).map(|_| g.rd_points(perm_chunks)).collect();
    let lk_prod: Vec<String> = (0..np).map(|_| g.rd_points(nl)).collect();
    let rand_c = g.rd_point("rand");
    let y = g.squeeze("y");
    let h_c = g.rd_points(dom.quotient_poly_degree as usize);
    let x = g.squeeze("x");
    let inst_ev: Vec<String> = (0..np).map(|_| g.rd_scalars(cs.instance_queries.len())).collect();
    let adv_ev: Vec<String> = (0..np).map(|_| g.rd_scalars(cs.advice_queries.len())).collect();
    let fix_ev = g.rd_scalars(cs.fixed_queries.len());
    let rand_ev = g.rd_scalar("random_eval");
    let perm_common = g.rd_scalars(vk.permutation.commitments.len());
    // per proof: set i at offset 3i: eval, next, (last if not the last set)
    let perm_ev: Vec<String> = (0..np).map(|_| g.rd_scalars(3 * perm_chunks - 1)).collect();
    // per proof: lookup i at offset 5i: prod, next, inp, inp_inv, tab
    let lk_ev: Vec<String> = (0..np).map(|_| g.rd_scalars(5 * nl)).collect();
    let pset_eval = |pi: usize, i: usize| fat(&perm_ev[pi], 3 * i);
    let pset_next = |pi: usize, i: usize| fat(&perm_ev[pi], 3 * i + 1);
    let pset_last = |pi: usize, i: usize| fat(&perm_ev[pi], 3 * i + 2);
    let lk = |pi: usize, i: usize, f: usize| fat(&lk_ev[pi], 5 * i + f);

    // --- vanishing argument ---
    let xn = g.bind(format!("Fp.sqr_n({k}n, {x})"));
    g.log("xn", &xn);
    let bf = cs.blinding_factors();
    let one = g.one.clone();
    let zero = g.zero.clone();
    let xn1 = g.sub(&xn, &one);
    let bw = g.konst(dom.barycentric_weight);
    let common = g.mul(&xn1, &bw);
    let mut l_evals = vec![];
    for r in -((bf + 1) as i32)..=0 {
        let wr = g.konst(rot_const(r));
        let d = g.sub(&x, &wr);
        let di = g.inv(&d);
        let t = g.mul(&di, &common);
        l_evals.push(g.mul(&t, &wr));
    }
    let l_last = l_evals[0].clone();
    let mut l_blind = zero.clone();
    for e in &l_evals[1..1 + bf] {
        l_blind = g.add(&l_blind, e);
    }
    let l_0 = l_evals[1 + bf].clone();
    g.log("l_last", &l_last);
    g.log("l_blind", &l_blind);
    g.log("l_0", &l_0);
    let l_lb = g.add(&l_last, &l_blind);
    let active = g.sub(&one, &l_lb);

    // expressions, folded into h = h*y + e as soon as each is produced
    let mut h = zero.clone();
    let mut ne = 0usize;
    let mut push = |g: &mut Gen, h: &mut String, e: String| {
        g.log(&format!("expr{ne}"), &e);
        ne += 1;
        let t = g.mul(h, &y);
        *h = g.add(&t, &e);
    };
    for pi in 0..np {
        let fe: Vec<String> = (0..cs.fixed_queries.len()).map(|i| fat(&fix_ev, i)).collect();
        let ae: Vec<String> = (0..cs.advice_queries.len()).map(|i| fat(&adv_ev[pi], i)).collect();
        let ie: Vec<String> = (0..cs.instance_queries.len()).map(|i| fat(&inst_ev[pi], i)).collect();
        for gate in cs.gates.iter() {
            for poly in gate.polynomials() {
                let v = g.expr(poly, &fe, &ae, &ie);
                push(&mut g, &mut h, v);
            }
        }
        let col_eval = |c: &crate::plonk::Column<Any>| -> String {
            let qi = cs.get_any_query_index(*c);
            match c.column_type() {
                Any::Advice => ae[qi].clone(),
                Any::Fixed => fe[qi].clone(),
                Any::Instance => ie[qi].clone(),
            }
        };
        if perm_chunks > 0 {
            let t = g.sub(&one, &pset_eval(pi, 0));
            let e = g.mul(&l_0, &t);
            push(&mut g, &mut h, e);
            let last = pset_eval(pi, perm_chunks - 1);
            let s = g.sq(&last);
            let t = g.sub(&s, &last);
            let e = g.mul(&t, &l_last);
            push(&mut g, &mut h, e);
        }
        for i in 1..perm_chunks {
            let t = g.sub(&pset_eval(pi, i), &pset_last(pi, i - 1));
            let e = g.mul(&t, &l_0);
            push(&mut g, &mut h, e);
        }
        for (ci, cols) in cs.permutation.columns.chunks(chunk_len).enumerate() {
            let mut left = pset_next(pi, ci);
            for (j, c) in cols.iter().enumerate() {
                let ev = col_eval(c);
                let bp = g.mul(&beta, &fat(&perm_common, ci * chunk_len + j));
                let t = g.add(&ev, &bp);
                let t = g.add(&t, &gamma);
                left = g.mul(&left, &t);
            }
            let mut right = pset_eval(pi, ci);
            let bx = g.mul(&beta, &x);
            let dpow = g.konst(Fp::DELTA.pow_vartime([(ci * chunk_len) as u64]));
            let mut cur_delta = g.mul(&bx, &dpow);
            let delta = g.konst(Fp::DELTA);
            for c in cols.iter() {
                let ev = col_eval(c);
                let t = g.add(&ev, &cur_delta);
                let t = g.add(&t, &gamma);
                right = g.mul(&right, &t);
                cur_delta = g.mul(&cur_delta, &delta);
            }
            let d = g.sub(&left, &right);
            let e = g.mul(&d, &active);
            push(&mut g, &mut h, e);
        }
        for (i, arg) in cs.lookups.iter().enumerate() {
            let (prod, next, inp, inp_inv, tab) = (lk(pi, i, 0), lk(pi, i, 1), lk(pi, i, 2), lk(pi, i, 3), lk(pi, i, 4));
            let t0 = g.sub(&one, &prod);
            let e = g.mul(&l_0, &t0);
            push(&mut g, &mut h, e);
            let s = g.sq(&prod);
            let t1 = g.sub(&s, &prod);
            let e = g.mul(&l_last, &t1);
            push(&mut g, &mut h, e);
            let a = g.add(&inp, &beta);
            let b = g.add(&tab, &gamma);
            let left = g.mul(&next, &a);
            let left = g.mul(&left, &b);
            let mut cin = zero.clone();
            for ex in arg.input_expressions.iter() {
                let v = g.expr(ex, &fe, &ae, &ie);
                let t = g.mul(&cin, &theta);
                cin = g.add(&t, &v);
            }
            let mut ctab = zero.clone();
            for ex in arg.table_expressions.iter() {
                let v = g.expr(ex, &fe, &ae, &ie);
                let t = g.mul(&ctab, &theta);
                ctab = g.add(&t, &v);
            }
            let ib = g.add(&cin, &beta);
            let tg = g.add(&ctab, &gamma);
            let right = g.mul(&prod, &ib);
            let right = g.mul(&right, &tg);
            let d = g.sub(&left, &right);
            let e = g.mul(&d, &active);
            push(&mut g, &mut h, e);
            let dd = g.sub(&inp, &tab);
            let e = g.mul(&l_0, &dd);
            push(&mut g, &mut h, e);
            let d2 = g.sub(&inp, &inp_inv);
            let t = g.mul(&dd, &d2);
            let e = g.mul(&t, &active);
            push(&mut g, &mut h, e);
        }
    }
    g.log("h_fold", &h);
    let xn1i = g.inv(&xn1);
    let expected_h = g.mul(&h, &xn1i);
    g.log("expected_h_eval", &expected_h);
    let mut h_msm = g.ms_empty();
    for i in (0..dom.quotient_poly_degree as usize).rev() {
        h_msm = g.ms_scale(&h_msm, &xn);
        h_msm = g.ms_push(&h_msm, &one, &pat(&h_c, i));
    }

    // --- queries, in verify_proof's order ---
    let last_rot = -((bf + 1) as i32);
    let mut queries: Vec<(Key, i32, String)> = vec![];
    for pi in 0..np {
        for (qi, (col, at)) in cs.instance_queries.iter().enumerate() {
            queries.push((Key::Inst(pi, col.index()), at.0, fat(&inst_ev[pi], qi)));
        }
        for (qi, (col, at)) in cs.advice_queries.iter().enumerate() {
            queries.push((Key::Adv(pi, col.index()), at.0, fat(&adv_ev[pi], qi)));
        }
        for i in 0..perm_chunks {
            queries.push((Key::PermProd(pi, i), 0, pset_eval(pi, i)));
            queries.push((Key::PermProd(pi, i), 1, pset_next(pi, i)));
        }
        for i in (0..perm_chunks).rev().skip(1) {
            queries.push((Key::PermProd(pi, i), last_rot, pset_last(pi, i)));
        }
        for i in 0..nl {
            queries.push((Key::LkProd(pi, i), 0, lk(pi, i, 0)));
            queries.push((Key::LkIn(pi, i), 0, lk(pi, i, 2)));
            queries.push((Key::LkTab(pi, i), 0, lk(pi, i, 4)));
            queries.push((Key::LkIn(pi, i), -1, lk(pi, i, 3)));
            queries.push((Key::LkProd(pi, i), 1, lk(pi, i, 1)));
        }
    }
    for (qi, (col, at)) in cs.fixed_queries.iter().enumerate() {
        queries.push((Key::Fixed(col.index()), at.0, fat(&fix_ev, qi)));
    }
    for i in 0..vk.permutation.commitments.len() {
        queries.push((Key::PermCommon(i), 0, fat(&perm_common, i)));
    }
    queries.push((Key::H, 0, expected_h.clone()));
    queries.push((Key::Rand, 0, rand_ev.clone()));

    let point_of = |key: Key| -> String {
        match key {
            Key::Inst(p, i) => insts[p][i].clone(),
            Key::Adv(p, i) => pat(&adv[p], i),
            Key::PermProd(p, i) => pat(&perm_prod[p], i),
            Key::LkProd(p, i) => pat(&lk_prod[p], i),
            Key::LkIn(p, i) => pat(&lk_perm[p], 2 * i),
            Key::LkTab(p, i) => pat(&lk_perm[p], 2 * i + 1),
            Key::Fixed(i) => format!("VK_FIXED{i}()"),
            Key::PermCommon(i) => format!("VK_PERM{i}()"),
            Key::Rand => rand_c.clone(),
            Key::H => unreachable!(),
        }
    };

    // --- multiopen::verify_proof ---
    let x1 = g.squeeze("x1");
    let x2 = g.squeeze("x2");
    let mut point_index: IndexMap<i32, usize> = IndexMap::new();
    let mut cmap: IndexMap<Key, Vec<usize>> = IndexMap::new();
    for (key, rot, _) in &queries {
        let n = point_index.len();
        let idx = *point_index.entry(*rot).or_insert(n);
        cmap.entry(*key).or_default().push(idx);
    }
    let mut set_ids: IndexMap<BTreeSet<usize>, usize> = IndexMap::new();
    let mut cset: IndexMap<Key, BTreeSet<usize>> = IndexMap::new();
    for (key, idxs) in &cmap {
        let s: BTreeSet<usize> = idxs.iter().cloned().collect();
        cset.insert(*key, s.clone());
        let n = set_ids.len();
        set_ids.entry(s).or_insert(n);
    }
    let mut cevals: IndexMap<Key, Vec<Option<String>>> =
        cset.iter().map(|(k, s)| (*k, vec![None; s.len()])).collect();
    for (key, rot, ev) in &queries {
        let pidx = point_index[rot];
        let s: Vec<usize> = cset[key].iter().cloned().collect();
        let pos = s.iter().position(|i| *i == pidx).unwrap();
        let slot = &mut cevals.get_mut(key).unwrap()[pos];
        assert!(slot.is_none(), "duplicate query");
        *slot = Some(ev.clone());
    }
    let inv_point: HashMap<usize, i32> = point_index.iter().map(|(r, i)| (*i, *r)).collect();
    let mut point_sets: Vec<Vec<i32>> = vec![vec![]; set_ids.len()];
    for (s, sid) in &set_ids {
        for pi in s {
            point_sets[*sid].push(inv_point[pi]);
        }
    }
    let mut rot_pt: HashMap<i32, String> = HashMap::new();
    for r in point_index.keys() {
        let v = if *r == 0 {
            x.clone()
        } else {
            let c = g.konst(rot_const(*r));
            g.mul(&x, &c)
        };
        rot_pt.insert(*r, v);
    }
    let nsets = set_ids.len();
    let mut q_msm: Vec<String> = (0..nsets).map(|_| g.ms_empty()).collect();
    let mut q_pow: Vec<String> = vec![one.clone(); nsets];
    let mut q_evals: Vec<Vec<String>> = point_sets.iter().map(|s| vec![zero.clone(); s.len()]).collect();
    for (key, _) in cmap.iter().rev() {
        let sid = set_ids[&cset[key]];
        let pw = q_pow[sid].clone();
        if *key == Key::H {
            let m = g.ms_scale(&h_msm, &pw);
            q_msm[sid] = g.ms_cat(&q_msm[sid].clone(), &m);
        } else {
            q_msm[sid] = g.ms_push(&q_msm[sid].clone(), &pw, &point_of(*key));
        }
        let evs: Vec<String> = cevals[key].iter().map(|e| e.clone().unwrap()).collect();
        for (j, ev) in evs.iter().enumerate() {
            let t = g.mul(ev, &pw);
            q_evals[sid][j] = g.add(&q_evals[sid][j].clone(), &t);
        }
        q_pow[sid] = g.mul(&pw, &x1);
    }
    let q_prime = g.rd_point("qprime");
    let x3 = g.squeeze("x3");
    let us = g.rd_scalars(nsets);
    let mut msm_eval = zero.clone();
    for sid in 0..nsets {
        let pts: Vec<String> = point_sets[sid].iter().map(|r| rot_pt[r].clone()).collect();
        // r(x3) by Lagrange's formula: the same value as halo2's interpolate-then-evaluate
        let mut r_eval = zero.clone();
        for j in 0..pts.len() {
            let mut term = q_evals[sid][j].clone();
            for m in 0..pts.len() {
                if m == j {
                    continue;
                }
                let num = g.sub(&x3, &pts[m]);
                let den = g.sub(&pts[j], &pts[m]);
                let deni = g.inv(&den);
                let f = g.mul(&num, &deni);
                term = g.mul(&term, &f);
            }
            r_eval = g.add(&r_eval, &term);
        }
        let mut ev = g.sub(&fat(&us, sid), &r_eval);
        for p in &pts {
            let d = g.sub(&x3, p);
            let di = g.inv(&d);
            ev = g.mul(&ev, &di);
        }
        let t = g.mul(&msm_eval, &x2);
        msm_eval = g.add(&t, &ev);
    }
    g.log("msm_eval", &msm_eval);
    let x4 = g.squeeze("x4");
    let mut msm = g.ms_empty();
    msm = g.ms_push(&msm, &one, &q_prime);
    let mut v = msm_eval.clone();
    for sid in 0..nsets {
        msm = g.ms_scale(&msm, &x4);
        msm = g.ms_cat(&msm, &q_msm[sid].clone());
        let t = g.mul(&v, &x4);
        v = g.add(&t, &fat(&us, sid));
    }
    g.log("v", &v);

    // --- commitment::verify_proof (IPA) ---
    let s_poly = g.rd_point("spoly");
    let xi = g.squeeze("xi");
    msm = g.ms_push(&msm, &xi, &s_poly);
    let z = g.squeeze("z");
    let mut rounds = vec![];
    for j in 0..k {
        let l = g.rd_point(&format!("L{j}"));
        let r = g.rd_point(&format!("R{j}"));
        let u = g.squeeze("u_j");
        rounds.push((l, r, u));
    }
    let mut u_list = vec![];
    for (l, r, u) in &rounds {
        let ui = g.inv(u);
        msm = g.ms_push(&msm, &ui, l);
        msm = g.ms_push(&msm, u, r);
        u_list.push(u.clone());
    }
    let c = g.rd_scalar("c");
    let f = g.rd_scalar("f");
    let neg_c = g.neg(&c);
    let mut tmp = one.clone();
    let mut cur = x3.clone();
    for u in u_list.iter().rev() {
        let t = g.mul(u, &cur);
        let t = g.add(&one, &t);
        tmp = g.mul(&tmp, &t);
        cur = g.sq(&cur);
    }
    let b = tmp;
    g.log("b", &b);
    let ncb = g.mul(&neg_c, &b);
    let u_scalar = g.mul(&ncb, &z);
    let w_scalar = g.neg(&f);
    g.log("msm_w", &w_scalar);
    g.log("msm_u", &u_scalar);
    // g scalars: compute_s(u, -c), plus the constant term -v at G_0
    let us_rev: Vec<String> = u_list.iter().rev().cloned().collect();
    let s_all = g.bind_t(format!("L.sub_head(L.compute_s([{}], {neg_c}), {v})", us_rev.join(", ")), "+List<Fp.Fp>");
    {
        let st = g.st();
        g.next_st(format!("L.log_list({s_all}, {st})"));
    }

    // --- the final check: the whole MSM must be the identity ---
    msm = g.ms_push(&msm, &w_scalar, "PARAM_W()");
    msm = g.ms_push(&msm, &u_scalar, "PARAM_U()");
    let ps_v = g.bind_t(format!("List.append(&2, V.Pt, L.ms_ps({msm}), G_ALL())"), "+List<V.Pt>");
    let ss_v = g.bind_t(format!("List.append(&2, Wd.W, L.words_list(L.ms_ss({msm})), L.words_list({s_all}))"), "+List<Wd.W>");
    let total = g.bind_t(format!("MSM.msm({msm_depth}n, {ps_v}, {ss_v})"), "V.Pt");
    {
        let st = g.st();
        g.next_st(format!("L.lgp({st}, \"msm_result\", {total})"));
    }
    g.check(&format!("V.is_identity({total})"));

    let mut out = String::new();
    out.push_str("# GENERATED by the Zebend halo2 codegen (zebend_codegen.rs). Do not edit.\n");
    out.push_str("import Base\nimport ../lib/words.bend as Wd\nimport ../lib/fp.bend as Fp\nimport ../lib/fq.bend as Fq\nimport ../lib/vesta.bend as V\nimport ../lib/msm.bend as MSM\nimport ./vlib.bend as L\n\n");
    for d in &g.const_defs {
        out.push_str(d);
        out.push('\n');
    }
    for d in &point_defs {
        out.push_str(d);
        out.push('\n');
    }
    let mut lines = vec!["  +st0 = L.st_new(pr)".to_string()];
    g.types.insert("st0".into(), "L.St".into());
    lines.extend(g.lines.iter().cloned());
    let result = g.st();
    out.push_str(&segment(&lines, &g.types, &result, 16));
    let _ = Rotation::cur();
    out
}

/// The VK's transcript representative (for cross-checking against other dumps).
pub fn transcript_repr(vk: &VerifyingKey<vesta::Affine>) -> Fp {
    vk.transcript_repr
}
