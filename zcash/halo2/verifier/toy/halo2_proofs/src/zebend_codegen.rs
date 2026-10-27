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
        self.bind_t(expr, "L.BF")
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
        self.const_defs.push(format!("def {name}() -> L.BF:\n  L.BF0{{Fp.Fp{{{lit}}}}}\n"));
        self.consts.insert(limbs, name.clone());
        format!("{name}()")
    }
    fn mul(&mut self, a: &str, b: &str) -> String {
        self.bind(format!("L.bmul({a}, {b})"))
    }
    fn add(&mut self, a: &str, b: &str) -> String {
        self.bind(format!("L.badd({a}, {b})"))
    }
    fn sub(&mut self, a: &str, b: &str) -> String {
        self.bind(format!("L.bsub({a}, {b})"))
    }
    fn neg(&mut self, a: &str) -> String {
        self.bind(format!("L.bneg({a})"))
    }
    fn inv(&mut self, a: &str) -> String {
        self.bind(format!("L.binv({a})"))
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
        self.next_st(format!("L.blgf({st}, \"{name}\", {v})"));
    }
    fn check(&mut self, cond: &str) {
        let st = self.st();
        self.next_st(format!("L.check({st}, {cond})"));
    }
    fn squeeze(&mut self, name: &str) -> String {
        let st = self.st();
        let r = self.fresh("r");
        self.bind_as(&r, format!("L.squeeze({st})"), "L.SF");
        let v = self.bind(format!("L.bx(L.sf_v({r}))"));
        self.next_st(format!("L.sf_st({r})"));
        self.log(name, &v);
        v
    }
    fn rd_scalar(&mut self, name: &str) -> String {
        let st = self.st();
        let r = self.fresh("r");
        self.bind_as(&r, format!("L.rd_scalar({st})"), "L.SF");
        let v = self.bind(format!("L.bx(L.sf_v({r}))"));
        self.next_st(format!("L.sf_st({r})"));
        self.log(name, &v);
        v
    }
    fn rd_point(&mut self, name: &str) -> String {
        let st = self.st();
        let r = self.fresh("r");
        self.bind_as(&r, format!("L.rd_point({st})"), "L.SP");
        let p = self.fresh(&format!("p_{name}_"));
        self.bind_as(&p, format!("L.bpt(L.sp_p({r}))"), "L.BP");
        self.next_st(format!("L.sp_st({r})"));
        p
    }
    fn rd_ival(&mut self) -> String {
        let st = self.st();
        let r = self.fresh("r");
        self.bind_as(&r, format!("L.rd_ival({st})"), "L.SF");
        let v = self.bind(format!("L.bx(L.sf_v({r}))"));
        self.next_st(format!("L.sf_st({r})"));
        v
    }
    fn ab_point(&mut self, p: &str) {
        let st = self.st();
        self.next_st(format!("L.bab_point({st}, {p})"));
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
        self.bind_t(format!("L.bms_push({m}, {s}, {p})"), "L.MS")
    }
    fn ms_scale(&mut self, m: &str, f: &str) -> String {
        self.bind_t(format!("L.bms_scale({m}, {f})"), "L.MS")
    }
    fn ms_cat(&mut self, a: &str, b: &str) -> String {
        self.bind_t(format!("L.ms_cat({a}, {b})"), "L.MS")
    }
    fn ab_scalar(&mut self, v: &str) {
        let st = self.st();
        self.next_st(format!("L.bab_scalar({st}, {v})"));
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
    format!("L.bfat({i}n, {list})")
}

fn pat(list: &str, i: usize) -> String {
    format!("L.bpat({i}n, {list})")
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
    point_defs.push(format!("def PARAM_W() -> L.BP:\n  L.BP0{{{}}}\n", point_lit(&params.w)));
    point_defs.push(format!("def PARAM_U() -> L.BP:\n  L.BP0{{{}}}\n", point_lit(&params.u)));
    let max_len = inst_len.iter().cloned().max().unwrap_or(0);
    for j in 0..max_len {
        point_defs.push(format!("def G_LAG{j}() -> L.BP:\n  L.BP0{{{}}}\n", point_lit(&params.g_lagrange[j])));
    }
    let g_list: Vec<String> = params.g.iter().map(point_lit).collect();
    point_defs.push(format!("def G_ALL() -> +List<V.Pt>:\n  [{}]\n", g_list.join(",\n   ")));
    for (i, c) in vk.fixed_commitments.iter().enumerate() {
        point_defs.push(format!("def VK_FIXED{i}() -> L.BP:\n  L.BP0{{{}}}\n", point_lit(c)));
    }
    for (i, c) in vk.permutation.commitments.iter().enumerate() {
        point_defs.push(format!("def VK_PERM{i}() -> L.BP:\n  L.BP0{{{}}}\n", point_lit(c)));
    }

    // instance commitments: commit_lagrange(instance, Blind::default()) = sum inst_j G_lag_j + 1*W
    let mut insts: Vec<Vec<String>> = vec![];
    for _ in 0..np {
        let mut cols = vec![];
        for len in inst_len.iter() {
            let mut acc = "PARAM_W()".to_string();
            for j in 0..*len {
                let v = g.rd_ival();
                let t = g.bind_t(format!("L.bsmul(G_LAG{j}(), {v})"), "L.BP");
                acc = g.bind_t(format!("L.bpadd({acc}, {t})"), "L.BP");
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
    let xn = g.bind(format!("L.bsqrn({k}n, {x})"));
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
    let us_rev: Vec<String> = us_rev.iter().map(|u| format!("L.ub({u})")).collect();
    let s_all = g.bind_t(format!("L.sub_head(L.compute_s([{}], L.ub({neg_c})), L.ub({v}))", us_rev.join(", ")), "+List<Fp.Fp>");
    {
        let st = g.st();
        g.next_st(format!("L.log_list({s_all}, {st})"));
    }

    // --- the final check: the whole MSM must be the identity ---
    msm = g.ms_push(&msm, &w_scalar, "PARAM_W()");
    msm = g.ms_push(&msm, &u_scalar, "PARAM_U()");
    let ps_v = g.bind_t(format!("List.append(&2, V.Pt, L.ms_ps({msm}), G_ALL())"), "+List<V.Pt>");
    let ss_v = g.bind_t(format!("List.append(&2, Wd.W, L.words_list(L.ms_ss({msm})), L.words_list({s_all}))"), "+List<Wd.W>");
    let total = g.bind_t(format!("L.bpt(MSM.msm({msm_depth}n, {ps_v}, {ss_v}))"), "L.BP");
    {
        let st = g.st();
        g.next_st(format!("L.blgp({st}, \"msm_result\", {total})"));
    }
    g.check(&format!("L.bis_identity({total})"));

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
    out.push_str(&segment(&lines, &g.types, &result, 300));
    let _ = Rotation::cur();
    out
}

/// The VK's transcript representative (for cross-checking against other dumps).
pub fn transcript_repr(vk: &VerifyingKey<vesta::Affine>) -> Fp {
    vk.transcript_repr
}

// ===========================================================================================
// Bundle-generic verifier: the number of circuit instances (actions) is a runtime input.
// Per-proof work is generated once (pp_expr: gate/permutation/lookup terms folded into h;
// pp_qa: that proof's multiopen accumulation) and run in runtime loops.
// ===========================================================================================

/// Like `segment`, for a named chain with given entry parameters, result expression and type.
fn chain(
    name: &str,
    init: &[(String, String)],
    lines: &[String],
    types: &HashMap<String, String>,
    result: &str,
    ret_ty: &str,
    max_lines: usize,
) -> String {
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
    let toks = |s: &str| -> Vec<String> {
        tokens(s).into_iter().map(|(a, b)| s[a..b].to_string()).filter(|t| types.contains_key(t)).collect()
    };
    let parsed: Vec<(String, Vec<String>)> = lines
        .iter()
        .map(|l| {
            let (lhs, rhs) = l.trim().trim_start_matches('+').split_once(" = ").unwrap();
            (lhs.to_string(), toks(rhs))
        })
        .collect();
    let n = parsed.len();
    let mut live_after: Vec<BTreeSet<String>> = vec![BTreeSet::new(); n];
    let mut live: BTreeSet<String> = toks(result).into_iter().collect();
    for i in (0..n).rev() {
        live_after[i] = live.clone();
        live.remove(&parsed[i].0);
        live.extend(parsed[i].1.iter().cloned());
    }
    let big = |v: &String| matches!(types[v].as_str(), "L.SF" | "L.SP" | "L.SL" | "L.PL" | "L.PLL" | "L.SLL" | "L.HS");
    let mut bounds = vec![0];
    let mut start = 0;
    for i in 0..n.saturating_sub(1) {
        if i + 1 - start >= max_lines && !live_after[i].iter().any(big) {
            bounds.push(i + 1);
            start = i + 1;
        }
    }
    bounds.push(n);
    let nseg = bounds.len() - 1;
    let mut defs = vec![];
    for si in 0..nseg {
        let (a, b) = (bounds[si], bounds[si + 1]);
        let fname = if si == 0 { name.to_string() } else { format!("{name}_{si}") };
        let params: Vec<String> = if si == 0 {
            init.iter().map(|(v, t)| format!("+{v}: {t}")).collect()
        } else {
            live_after[a - 1].iter().map(|v| format!("+{v}: {}", types[v])).collect()
        };
        let mut body = format!("def {fname}({}) -> {ret_ty}:\n", params.join(", "));
        for l in &lines[a..b] {
            body.push_str(l);
            body.push('\n');
        }
        if si + 1 < nseg {
            let args: Vec<String> = live_after[b - 1].iter().cloned().collect();
            body.push_str(&format!("  {name}_{}({})\n", si + 1, args.join(", ")));
        } else {
            body.push_str(&format!("  {result}\n"));
        }
        defs.push(body);
    }
    defs.reverse();
    defs.join("\n")
}

#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
enum PKey {
    Inst,
    Adv(usize),
    PermProd(usize),
    LkProd(usize),
    LkIn(usize),
    LkTab(usize),
}

impl Gen {
    /// Starts a new chain: fresh lines and state counter (constants stay shared).
    fn reset(&mut self) {
        self.lines.clear();
        self.st = 0;
    }
    fn param(&mut self, v: &str, ty: &str) -> String {
        self.types.insert(v.to_string(), ty.to_string());
        v.to_string()
    }
}

/// Emits a Bend module with `verify(pr: L.Proof, gs: +List<V.Pt>, np: Nat, ni: Nat) -> L.St`:
/// a bundle of `np` proofs (actions), each with `ni` instance values in its single instance
/// column; `gs` are the 2^k IPA generators (read at runtime).
pub fn bend_verifier_dyn(params: &Params<vesta::Affine>, vk: &VerifyingKey<vesta::Affine>, msm_depth: usize) -> String {
    let cs = &vk.cs;
    let dom = &vk.domain;
    assert_eq!(cs.num_instance_columns, 1, "bundle verifier assumes one instance column");
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
    let nl = cs.lookups.len();
    let chunk_len = vk.cs_degree - 2;
    let pc = cs.permutation.columns.chunks(chunk_len).count();
    let bf = cs.blinding_factors();
    let last_rot = -((bf + 1) as i32);
    let mut g = Gen::new();
    let mut out_defs: Vec<String> = vec![];

    // ---- query template (one proof), structured: (key, rotation, eval reference) ----
    #[derive(Clone)]
    enum Ev {
        Ie(usize),
        Ae(usize),
        Pe(usize),
        Le(usize),
        Fe(usize),
        Pc(usize),
        H,
        Rand,
    }
    #[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
    enum Q {
        P(PKey),
        Fixed(usize),
        PermCommon(usize),
        H,
        Rand,
    }
    let mut tq: Vec<(Q, i32, Ev)> = vec![];
    for (qi, (_col, at)) in cs.instance_queries.iter().enumerate() {
        tq.push((Q::P(PKey::Inst), at.0, Ev::Ie(qi)));
    }
    for (qi, (col, at)) in cs.advice_queries.iter().enumerate() {
        tq.push((Q::P(PKey::Adv(col.index())), at.0, Ev::Ae(qi)));
    }
    for i in 0..pc {
        tq.push((Q::P(PKey::PermProd(i)), 0, Ev::Pe(3 * i)));
        tq.push((Q::P(PKey::PermProd(i)), 1, Ev::Pe(3 * i + 1)));
    }
    for i in (0..pc).rev().skip(1) {
        tq.push((Q::P(PKey::PermProd(i)), last_rot, Ev::Pe(3 * i + 2)));
    }
    for i in 0..nl {
        tq.push((Q::P(PKey::LkProd(i)), 0, Ev::Le(5 * i)));
        tq.push((Q::P(PKey::LkIn(i)), 0, Ev::Le(5 * i + 2)));
        tq.push((Q::P(PKey::LkTab(i)), 0, Ev::Le(5 * i + 4)));
        tq.push((Q::P(PKey::LkIn(i)), -1, Ev::Le(5 * i + 3)));
        tq.push((Q::P(PKey::LkProd(i)), 1, Ev::Le(5 * i + 1)));
    }
    for (qi, (col, at)) in cs.fixed_queries.iter().enumerate() {
        tq.push((Q::Fixed(col.index()), at.0, Ev::Fe(qi)));
    }
    for i in 0..vk.permutation.commitments.len() {
        tq.push((Q::PermCommon(i), 0, Ev::Pc(i)));
    }
    tq.push((Q::H, 0, Ev::H));
    tq.push((Q::Rand, 0, Ev::Rand));
    // construct_intermediate_sets on the template: per-proof keys come first in every bundle,
    // and later proofs repeat the same keys, so sets and point indices are those of one proof.
    let mut point_index: IndexMap<i32, usize> = IndexMap::new();
    let mut cmap: IndexMap<Q, Vec<usize>> = IndexMap::new();
    for (key, rot, _) in &tq {
        let n = point_index.len();
        let idx = *point_index.entry(*rot).or_insert(n);
        cmap.entry(*key).or_default().push(idx);
    }
    let mut set_ids: IndexMap<BTreeSet<usize>, usize> = IndexMap::new();
    let mut cset: IndexMap<Q, BTreeSet<usize>> = IndexMap::new();
    for (key, idxs) in &cmap {
        let s: BTreeSet<usize> = idxs.iter().cloned().collect();
        cset.insert(*key, s.clone());
        let n = set_ids.len();
        set_ids.entry(s).or_insert(n);
    }
    // per key: evals in the set's point order
    let mut kev: IndexMap<Q, Vec<Option<Ev>>> = cset.iter().map(|(k, s)| (*k, vec![None; s.len()])).collect();
    for (key, rot, ev) in &tq {
        let pidx = point_index[rot];
        let s: Vec<usize> = cset[key].iter().cloned().collect();
        let pos = s.iter().position(|i| *i == pidx).unwrap();
        kev.get_mut(key).unwrap()[pos] = Some(ev.clone());
    }
    let inv_point: HashMap<usize, i32> = point_index.iter().map(|(r, i)| (*i, *r)).collect();
    let mut point_sets: Vec<Vec<i32>> = vec![vec![]; set_ids.len()];
    for (s, sid) in &set_ids {
        for pi in s {
            point_sets[*sid].push(inv_point[pi]);
        }
    }
    let nsets = set_ids.len();

    // ---- the QA record: per point set, the q-commitment MSM, the x1 power, the q evals ----
    let mut qa_fields: Vec<(String, String)> = vec![];
    for s in 0..nsets {
        qa_fields.push((format!("m{s}"), "L.MS".into()));
        qa_fields.push((format!("p{s}"), "L.BF".into()));
        for j in 0..point_sets[s].len() {
            qa_fields.push((format!("e{s}_{j}"), "L.BF".into()));
        }
    }
    let mut qa_def = String::from("type QA is Data:\n  QA{");
    qa_def.push_str(&qa_fields.iter().map(|(n, t)| format!("{n}: {t}")).collect::<Vec<_>>().join(", "));
    qa_def.push_str("}\n");
    out_defs.push(qa_def);
    for (fi, (f, t)) in qa_fields.iter().enumerate() {
        let pats: Vec<String> =
            (0..qa_fields.len()).map(|j| if j == fi { format!("+{f}") } else { "_".into() }).collect();
        out_defs.push(format!("def QA_{f}(q: QA) -> {t}:\n  QA{{{}}} = q\n  {f}\n", pats.join(", ")));
    }
    // emits a key's accumulation into the QA fields held in `cur` (field -> var)
    let accumulate = |g: &mut Gen, cur: &mut HashMap<String, String>, sid: usize, evs: Vec<String>, point: Option<String>, hmsm: Option<&str>, x1: &str| {
        let pw = cur[&format!("p{sid}")].clone();
        let m = cur[&format!("m{sid}")].clone();
        let m2 = if let Some(h) = hmsm {
            let sc = g.ms_scale(h, &pw);
            g.ms_cat(&m, &sc)
        } else {
            g.ms_push(&m, &pw, &point.unwrap())
        };
        cur.insert(format!("m{sid}"), m2);
        for (j, ev) in evs.iter().enumerate() {
            let t = g.mul(ev, &pw);
            let e = cur[&format!("e{sid}_{j}")].clone();
            let e2 = g.add(&e, &t);
            cur.insert(format!("e{sid}_{j}"), e2);
        }
        let p2 = g.mul(&pw, x1);
        cur.insert(format!("p{sid}"), p2);
    };
    let qa_build = |cur: &HashMap<String, String>| -> String {
        format!("QA{{{}}}", qa_fields.iter().map(|(f, _)| cur[f].clone()).collect::<Vec<_>>().join(", "))
    };

    // ---- pp_expr: one proof's expressions folded into h ----
    g.reset();
    let pnames = ["theta", "beta", "gamma", "x", "y", "l_0", "l_last", "active"];
    let mut init: Vec<(String, String)> = vec![];
    for n in pnames {
        g.param(n, "L.BF");
        init.push((n.into(), "L.BF".into()));
    }
    for n in ["fe", "pcv", "ae", "ie", "pe", "le"] {
        g.param(n, "+List<Fp.Fp>");
        init.push((n.into(), "+List<Fp.Fp>".into()));
    }
    g.param("h0", "L.BF");
    init.push(("h0".into(), "L.BF".into()));
    g.param("st0", "L.St");
    init.push(("st0".into(), "L.St".into()));
    {
        let one = g.one.clone();
        let zero = g.zero.clone();
        let fe: Vec<String> = (0..cs.fixed_queries.len()).map(|i| fat("fe", i)).collect();
        let ae: Vec<String> = (0..cs.advice_queries.len()).map(|i| fat("ae", i)).collect();
        let ie: Vec<String> = (0..cs.instance_queries.len()).map(|i| fat("ie", i)).collect();
        let mut h = "h0".to_string();
        let mut push = |g: &mut Gen, h: &mut String, e: String| {
            g.log("expr", &e);
            let t = g.mul(h, "y");
            *h = g.add(&t, &e);
        };
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
        let pe = |i: usize| fat("pe", i);
        if pc > 0 {
            let t = g.sub(&one, &pe(0));
            let e = g.mul("l_0", &t);
            push(&mut g, &mut h, e);
            let last = pe(3 * (pc - 1));
            let s = g.sq(&last);
            let t = g.sub(&s, &last);
            let e = g.mul(&t, "l_last");
            push(&mut g, &mut h, e);
        }
        for i in 1..pc {
            let t = g.sub(&pe(3 * i), &pe(3 * (i - 1) + 2));
            let e = g.mul(&t, "l_0");
            push(&mut g, &mut h, e);
        }
        for (ci, cols) in cs.permutation.columns.chunks(chunk_len).enumerate() {
            let mut left = pe(3 * ci + 1);
            for (j, c) in cols.iter().enumerate() {
                let ev = col_eval(c);
                let bp = g.mul("beta", &fat("pcv", ci * chunk_len + j));
                let t = g.add(&ev, &bp);
                let t = g.add(&t, "gamma");
                left = g.mul(&left, &t);
            }
            let mut right = pe(3 * ci);
            let bx = g.mul("beta", "x");
            let dpow = g.konst(Fp::DELTA.pow_vartime([(ci * chunk_len) as u64]));
            let mut cur_delta = g.mul(&bx, &dpow);
            let delta = g.konst(Fp::DELTA);
            for c in cols.iter() {
                let ev = col_eval(c);
                let t = g.add(&ev, &cur_delta);
                let t = g.add(&t, "gamma");
                right = g.mul(&right, &t);
                cur_delta = g.mul(&cur_delta, &delta);
            }
            let d = g.sub(&left, &right);
            let e = g.mul(&d, "active");
            push(&mut g, &mut h, e);
        }
        for (i, arg) in cs.lookups.iter().enumerate() {
            let lk = |f: usize| fat("le", 5 * i + f);
            let (prod, next, inp, inp_inv, tab) = (lk(0), lk(1), lk(2), lk(3), lk(4));
            let t0 = g.sub(&one, &prod);
            let e = g.mul("l_0", &t0);
            push(&mut g, &mut h, e);
            let s = g.sq(&prod);
            let t1 = g.sub(&s, &prod);
            let e = g.mul("l_last", &t1);
            push(&mut g, &mut h, e);
            let a = g.add(&inp, "beta");
            let b = g.add(&tab, "gamma");
            let left = g.mul(&next, &a);
            let left = g.mul(&left, &b);
            let mut cin = zero.clone();
            for ex in arg.input_expressions.iter() {
                let v = g.expr(ex, &fe, &ae, &ie);
                let t = g.mul(&cin, "theta");
                cin = g.add(&t, &v);
            }
            let mut ctab = zero.clone();
            for ex in arg.table_expressions.iter() {
                let v = g.expr(ex, &fe, &ae, &ie);
                let t = g.mul(&ctab, "theta");
                ctab = g.add(&t, &v);
            }
            let ib = g.add(&cin, "beta");
            let tg = g.add(&ctab, "gamma");
            let right = g.mul(&prod, &ib);
            let right = g.mul(&right, &tg);
            let d = g.sub(&left, &right);
            let e = g.mul(&d, "active");
            push(&mut g, &mut h, e);
            let dd = g.sub(&inp, &tab);
            let e = g.mul("l_0", &dd);
            push(&mut g, &mut h, e);
            let d2 = g.sub(&inp, &inp_inv);
            let t = g.mul(&dd, &d2);
            let e = g.mul(&t, "active");
            push(&mut g, &mut h, e);
        }
        let st = g.st();
        let lines = g.lines.clone();
        out_defs.push(chain("pp_expr", &init, &lines, &g.types, &format!("L.HS{{{h}, {st}}}"), "L.HS", 300));
    }
    out_defs.push(format!(
        "def ex_loop(aes: +List<+List<Fp.Fp>>, ies: +List<+List<Fp.Fp>>, pes: +List<+List<Fp.Fp>>, les: +List<+List<Fp.Fp>>, {}, +fe: +List<Fp.Fp>, +pcv: +List<Fp.Fp>, +h: L.BF, +st: L.St) -> L.HS:\n  match aes ies pes les:\n    case Con{{+ae, ar}} Con{{+ie, ir}} Con{{+pe, pr}} Con{{+le, lr}}:\n      +r = pp_expr({}, fe, pcv, ae, ie, pe, le, h, st)\n      ex_loop(ar, ir, pr, lr, {}, fe, pcv, L.hs_h(r), L.hs_st(r))\n    case _ _ _ _:\n      L.HS{{h, st}}\n",
        pnames.iter().map(|n| format!("+{n}: L.BF")).collect::<Vec<_>>().join(", "),
        pnames.join(", "),
        pnames.join(", ")
    ));

    // ---- pp_qa: one proof's keys, in reverse insertion order ----
    g.reset();
    let mut init: Vec<(String, String)> = vec![("q".into(), "QA".into())];
    g.param("q", "QA");
    for n in ["x1"] {
        g.param(n, "L.BF");
        init.push((n.into(), "L.BF".into()));
    }
    for n in ["ae", "ie", "pe", "le"] {
        g.param(n, "+List<Fp.Fp>");
        init.push((n.into(), "+List<Fp.Fp>".into()));
    }
    for n in ["ap", "lp", "pp", "kp"] {
        g.param(n, "+List<V.Pt>");
        init.push((n.into(), "+List<V.Pt>".into()));
    }
    g.param("ic", "L.BP");
    init.push(("ic".into(), "L.BP".into()));
    {
        let mut cur: HashMap<String, String> = HashMap::new();
        for (f, t) in &qa_fields {
            let v = g.bind_t(format!("QA_{f}(q)"), t);
            cur.insert(f.clone(), v);
        }
        let ev_ref = |e: &Ev| -> String {
            match e {
                Ev::Ie(i) => fat("ie", *i),
                Ev::Ae(i) => fat("ae", *i),
                Ev::Pe(i) => fat("pe", *i),
                Ev::Le(i) => fat("le", *i),
                _ => unreachable!(),
            }
        };
        let per: Vec<Q> = cmap.keys().filter(|k| matches!(k, Q::P(_))).cloned().collect();
        for key in per.iter().rev() {
            let Q::P(pk) = key else { unreachable!() };
            let point = match pk {
                PKey::Inst => "ic".to_string(),
                PKey::Adv(i) => pat("ap", *i),
                PKey::PermProd(i) => pat("pp", *i),
                PKey::LkProd(i) => pat("kp", *i),
                PKey::LkIn(i) => pat("lp", 2 * i),
                PKey::LkTab(i) => pat("lp", 2 * i + 1),
            };
            let sid = set_ids[&cset[key]];
            let evs: Vec<String> = kev[key].iter().map(|e| ev_ref(e.as_ref().unwrap())).collect();
            accumulate(&mut g, &mut cur, sid, evs, Some(point), None, "x1");
        }
        let res = qa_build(&cur);
        let lines = g.lines.clone();
        out_defs.push(chain("pp_qa", &init, &lines, &g.types, &res, "QA", 300));
    }
    out_defs.push(
        "def qa_loop(aes: +List<+List<Fp.Fp>>, ies: +List<+List<Fp.Fp>>, pes: +List<+List<Fp.Fp>>, les: +List<+List<Fp.Fp>>, aps: +List<+List<V.Pt>>, lps: +List<+List<V.Pt>>, pps: +List<+List<V.Pt>>, kps: +List<+List<V.Pt>>, ics: +List<V.Pt>, +x1: L.BF, +q: QA) -> QA:\n  match aes ies pes les aps lps pps kps ics:\n    case Con{+ae, ar} Con{+ie, ir} Con{+pe, pr} Con{+le, lr} Con{+ap, apr} Con{+lp, lpr} Con{+pp, ppr} Con{+kp, kpr} Con{+ic, icr}:\n      qa_loop(ar, ir, pr, lr, apr, lpr, ppr, kpr, icr, x1, pp_qa(q, x1, ae, ie, pe, le, ap, lp, pp, kp, L.bpt(ic)))\n    case _ _ _ _ _ _ _ _ _:\n      q\n"
            .to_string(),
    );

    // ---- the main chain ----
    g.reset();
    g.param("pr", "L.Proof");
    g.param("gs", "+List<V.Pt>");
    g.param("np", "Nat");
    g.param("ni", "Nat");
    let init: Vec<(String, String)> = vec![
        ("pr".into(), "L.Proof".into()),
        ("gs".into(), "+List<V.Pt>".into()),
        ("np".into(), "Nat".into()),
        ("ni".into(), "Nat".into()),
    ];
    g.bind_as("st0", "L.st_new(pr)".into(), "L.St");
    let one = g.one.clone();
    let zero = g.zero.clone();
    let mut point_defs = vec![];
    point_defs.push(format!("def PARAM_W() -> L.BP:\n  L.BP0{{{}}}\n", point_lit(&params.w)));
    point_defs.push(format!("def PARAM_U() -> L.BP:\n  L.BP0{{{}}}\n", point_lit(&params.u)));
    let nlag = (params.n as usize - (bf + 1)).min(32);
    let lag: Vec<String> = params.g_lagrange[..nlag].iter().map(point_lit).collect();
    point_defs.push(format!("def G_LAG() -> +List<V.Pt>:\n  [{}]\n", lag.join(",\n   ")));
    for (i, c) in vk.fixed_commitments.iter().enumerate() {
        point_defs.push(format!("def VK_FIXED{i}() -> L.BP:\n  L.BP0{{{}}}\n", point_lit(c)));
    }
    for (i, c) in vk.permutation.commitments.iter().enumerate() {
        point_defs.push(format!("def VK_PERM{i}() -> L.BP:\n  L.BP0{{{}}}\n", point_lit(c)));
    }
    // instance commitments, then vk.hash_into, then absorb them
    {
        let st = g.st();
        let r = g.fresh("r");
        g.bind_as(&r, format!("L.inst_comms({st}, np, ni, G_LAG(), L.upt(PARAM_W()))"), "L.PL");
        g.bind_as("ics", format!("L.pl_v({r})"), "+List<V.Pt>");
        g.next_st(format!("L.pl_st({r})"));
    }
    let repr = g.konst(vk.transcript_repr);
    g.ab_scalar(&repr);
    {
        let st = g.st();
        g.next_st(format!("L.ab_points(ics, {st})"));
    }
    let groups = |g: &mut Gen, name: &str, k: usize, pts: bool| {
        let st = g.st();
        let r = g.fresh("r");
        if pts {
            g.bind_as(&r, format!("L.rd_groups({st}, np, {k}n)"), "L.PLL");
            g.bind_as(name, format!("L.pll_v({r})"), "+List<+List<V.Pt>>");
            g.next_st(format!("L.pll_st({r})"));
        } else {
            g.bind_as(&r, format!("L.rd_sgroups({st}, np, {k}n)"), "L.SLL");
            g.bind_as(name, format!("L.sll_v({r})"), "+List<+List<Fp.Fp>>");
            g.next_st(format!("L.sll_st({r})"));
        }
    };
    groups(&mut g, "aps", cs.num_advice_columns, true);
    let theta = g.squeeze("theta");
    groups(&mut g, "lps", 2 * nl, true);
    let beta = g.squeeze("beta");
    let gamma = g.squeeze("gamma");
    groups(&mut g, "pps", pc, true);
    groups(&mut g, "kps", nl, true);
    let rand_c = g.rd_point("rand");
    let y = g.squeeze("y");
    let h_c = g.rd_points(dom.quotient_poly_degree as usize);
    let x = g.squeeze("x");
    groups(&mut g, "ies", cs.instance_queries.len(), false);
    groups(&mut g, "aes", cs.advice_queries.len(), false);
    let fix_ev = g.rd_scalars(cs.fixed_queries.len());
    let rand_ev = g.rd_scalar("random_eval");
    let perm_common = g.rd_scalars(vk.permutation.commitments.len());
    groups(&mut g, "pes", 3 * pc - 1, false);
    groups(&mut g, "les", 5 * nl, false);
    let xn = g.bind(format!("L.bsqrn({k}n, {x})"));
    g.log("xn", &xn);
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
    {
        let st = g.st();
        let r = g.fresh("r");
        g.bind_as(
            &r,
            format!("ex_loop(aes, ies, pes, les, {theta}, {beta}, {gamma}, {x}, {y}, {l_0}, {l_last}, {active}, {fix_ev}, {perm_common}, {zero}, {st})"),
            "L.HS",
        );
        g.bind_as("hnum", format!("L.hs_h({r})"), "L.BF");
        g.next_st(format!("L.hs_st({r})"));
    }
    g.log("h_fold", "hnum");
    let xn1i = g.inv(&xn1);
    let expected_h = g.mul("hnum", &xn1i);
    g.log("expected_h_eval", &expected_h);
    let mut h_msm = g.ms_empty();
    for i in (0..dom.quotient_poly_degree as usize).rev() {
        h_msm = g.ms_scale(&h_msm, &xn);
        h_msm = g.ms_push(&h_msm, &one, &pat(&h_c, i));
    }
    let x1 = g.squeeze("x1");
    let x2 = g.squeeze("x2");
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
    // QA init, then global keys (they come last in the commitment map, so first in reverse)
    let mut cur: HashMap<String, String> = HashMap::new();
    for (f, t) in &qa_fields {
        let v = if t == "L.MS" { g.ms_empty() } else if f.starts_with('p') { one.clone() } else { zero.clone() };
        cur.insert(f.clone(), v);
    }
    let glob: Vec<Q> = cmap.keys().filter(|k| !matches!(k, Q::P(_))).cloned().collect();
    for key in glob.iter().rev() {
        let sid = set_ids[&cset[key]];
        let evs: Vec<String> = kev[key]
            .iter()
            .map(|e| match e.as_ref().unwrap() {
                Ev::Fe(i) => fat(&fix_ev, *i),
                Ev::Pc(i) => fat(&perm_common, *i),
                Ev::H => expected_h.clone(),
                Ev::Rand => rand_ev.clone(),
                _ => unreachable!(),
            })
            .collect();
        match key {
            Q::H => accumulate(&mut g, &mut cur, sid, evs, None, Some(&h_msm.clone()), &x1),
            Q::Rand => accumulate(&mut g, &mut cur, sid, evs, Some(rand_c.clone()), None, &x1),
            Q::Fixed(i) => accumulate(&mut g, &mut cur, sid, evs, Some(format!("VK_FIXED{i}()")), None, &x1),
            Q::PermCommon(i) => accumulate(&mut g, &mut cur, sid, evs, Some(format!("VK_PERM{i}()")), None, &x1),
            Q::P(_) => unreachable!(),
        }
    }
    let q0 = g.bind_t(format!("{{{} : QA}}", qa_build(&cur)), "QA");
    let qa = g.bind_t(
        format!("qa_loop(L.rev_sll(aes), L.rev_sll(ies), L.rev_sll(pes), L.rev_sll(les), L.rev_pll(aps), L.rev_pll(lps), L.rev_pll(pps), L.rev_pll(kps), L.rev_pts(ics), {x1}, {q0})"),
        "QA",
    );
    let fieldv = |g: &mut Gen, f: &str| -> String {
        let t = qa_fields.iter().find(|(n, _)| n == f).unwrap().1.clone();
        g.bind_t(format!("QA_{f}({qa})"), &t)
    };
    let q_prime = g.rd_point("qprime");
    let x3 = g.squeeze("x3");
    let us = g.rd_scalars(nsets);
    let mut msm_eval = zero.clone();
    for sid in 0..nsets {
        let pts: Vec<String> = point_sets[sid].iter().map(|r| rot_pt[r].clone()).collect();
        let qe: Vec<String> = (0..pts.len()).map(|j| fieldv(&mut g, &format!("e{sid}_{j}"))).collect();
        let mut r_eval = zero.clone();
        for j in 0..pts.len() {
            let mut term = qe[j].clone();
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
        let qm = fieldv(&mut g, &format!("m{sid}"));
        msm = g.ms_cat(&msm, &qm);
        let t = g.mul(&v, &x4);
        v = g.add(&t, &fat(&us, sid));
    }
    g.log("v", &v);
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
    let mut cur_x = x3.clone();
    for u in u_list.iter().rev() {
        let t = g.mul(u, &cur_x);
        let t = g.add(&one, &t);
        tmp = g.mul(&tmp, &t);
        cur_x = g.sq(&cur_x);
    }
    g.log("b", &tmp);
    let ncb = g.mul(&neg_c, &tmp);
    let u_scalar = g.mul(&ncb, &z);
    let w_scalar = g.neg(&f);
    g.log("msm_w", &w_scalar);
    g.log("msm_u", &u_scalar);
    let us_rev: Vec<String> = u_list.iter().rev().map(|u| format!("L.ub({u})")).collect();
    let s_all = g.bind_t(format!("L.sub_head(L.compute_s([{}], L.ub({neg_c})), L.ub({v}))", us_rev.join(", ")), "+List<Fp.Fp>");
    {
        let st = g.st();
        g.next_st(format!("L.log_list({s_all}, {st})"));
    }
    msm = g.ms_push(&msm, &w_scalar, "PARAM_W()");
    msm = g.ms_push(&msm, &u_scalar, "PARAM_U()");
    let ps_v = g.bind_t(format!("List.append(&2, V.Pt, L.ms_ps({msm}), gs)"), "+List<V.Pt>");
    let ss_v = g.bind_t(format!("List.append(&2, Wd.W, L.words_list(L.ms_ss({msm})), L.words_list({s_all}))"), "+List<Wd.W>");
    let total = g.bind_t(format!("L.bpt(MSM.msm({msm_depth}n, {ps_v}, {ss_v}))"), "L.BP");
    {
        let st = g.st();
        g.next_st(format!("L.blgp({st}, \"msm_result\", {total})"));
    }
    g.check(&format!("L.bis_identity({total})"));
    let lines = g.lines.clone();
    let main_chain = chain("verify", &init, &lines, &g.types, &g.st(), "L.St", 300);

    let mut out = String::new();
    out.push_str("# GENERATED by the Zebend halo2 codegen (bend_verifier_dyn). Do not edit.\n");
    out.push_str("import Base\nimport ../lib/words.bend as Wd\nimport ../lib/fp.bend as Fp\nimport ../lib/fq.bend as Fq\nimport ../lib/vesta.bend as V\nimport ../lib/msm.bend as MSM\nimport ./vlib.bend as L\n\n");
    for d in &g.const_defs {
        out.push_str(d);
        out.push('\n');
    }
    for d in &point_defs {
        out.push_str(d);
        out.push('\n');
    }
    for d in &out_defs {
        out.push_str(d);
        out.push('\n');
    }
    out.push_str(&main_chain);
    out
}
