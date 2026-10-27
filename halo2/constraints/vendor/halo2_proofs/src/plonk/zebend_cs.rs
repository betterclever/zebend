#![allow(missing_docs, missing_debug_implementations)]
//! ZEBEND: full constraint-system + layout extraction (not part of upstream halo2_proofs).
//!
//! `Recorder` is an `Assignment` backend that records, for one synthesis of a circuit:
//! every region (name, synthesis order), every advice assignment (column, row, region,
//! namespaced annotation, witness value), every fixed assignment and fill, every selector
//! enablement (with the region that enabled it), and every copy constraint.
//!
//! `rebuild_vk_pinned` turns the recorded fixed values, selectors and copies back into a
//! `VerifyingKey` exactly as `keygen_vk` does (selector compression, permutation
//! assembly, commitments) and returns its pinned Debug string. Equality with the real VK's
//! pinned string shows the recorded layout IS the circuit the VK commits to.
//!
//! `cs_json` / `expr_json` serialise gates, lookups and the permutation columns.

use std::collections::BTreeMap;
use std::fmt::Write as _;

use ff::{Field, PrimeField};
use pasta_curves::{vesta, Fp};

use super::{
    circuit::{
        Advice, Any, Assignment, Column, ConstraintSystem, Expression, Fixed, Instance,
        Selector,
    },
    permutation, Assigned, Error, VerifyingKey,
};
use pasta_curves::arithmetic::CurveExt;
use crate::{
    arithmetic::CurveAffine,
    circuit::Value,
    poly::{batch_invert_assigned, commitment::Blind, commitment::Params, EvaluationDomain},
};

/// One recorded advice cell.
#[derive(Clone, Debug)]
pub struct AdviceCell {
    pub value: Fp,
    pub known: bool,
    pub region: Option<usize>,
    pub name: String,
    /// global assignment counter (synthesis order)
    pub order: usize,
    /// how many times this cell was assigned
    pub writes: usize,
}

#[derive(Clone, Debug)]
pub struct Copy {
    pub left: (Any, usize, usize),
    pub right: (Any, usize, usize),
    pub region: Option<usize>,
    pub order: usize,
}

pub struct Recorder {
    pub n: usize,
    pub usable: usize,
    pub instance: Vec<Vec<Fp>>,
    pub regions: Vec<String>,
    cur: Option<usize>,
    ns: Vec<String>,
    counter: usize,
    pub advice: Vec<Vec<Option<AdviceCell>>>,
    pub fixed: Vec<Vec<Option<Fp>>>,
    pub fixed_names: BTreeMap<(usize, usize), (Option<usize>, String)>,
    pub selectors: Vec<Vec<bool>>,
    pub selector_region: BTreeMap<(usize, usize), Option<usize>>,
    pub copies: Vec<Copy>,
    pub instance_reads: Vec<(usize, usize)>,
}

fn kind(c: &Any) -> &'static str {
    match c {
        Any::Advice => "a",
        Any::Fixed => "f",
        Any::Instance => "i",
    }
}

impl Recorder {
    pub fn new(cs: &ConstraintSystem<Fp>, k: u32, instance: Vec<Vec<Fp>>) -> Self {
        let n = 1usize << k;
        Recorder {
            n,
            usable: n - (cs.blinding_factors() + 1),
            instance,
            regions: vec![],
            cur: None,
            ns: vec![],
            counter: 0,
            advice: vec![vec![None; n]; cs.num_advice_columns],
            fixed: vec![vec![None; n]; cs.num_fixed_columns],
            fixed_names: BTreeMap::new(),
            selectors: vec![vec![false; n]; cs.num_selectors],
            selector_region: BTreeMap::new(),
            copies: vec![],
            instance_reads: vec![],
        }
    }

    fn path(&self, ann: String) -> String {
        let mut s = self.ns.join("/");
        if !s.is_empty() {
            s.push_str(" :: ");
        }
        s.push_str(&ann);
        s
    }

    fn next(&mut self) -> usize {
        self.counter += 1;
        self.counter
    }
}

fn eval_value<VR: Into<Assigned<Fp>>>(v: Value<VR>) -> (Fp, bool) {
    let mut out = (Fp::ZERO, false);
    v.map(|v| out = (v.into().evaluate(), true));
    out
}

impl Assignment<Fp> for Recorder {
    fn enter_region<NR, N>(&mut self, name_fn: N)
    where
        NR: Into<String>,
        N: FnOnce() -> NR,
    {
        assert!(self.cur.is_none());
        self.regions.push(name_fn().into());
        self.cur = Some(self.regions.len() - 1);
    }

    fn exit_region(&mut self) {
        self.cur = None;
    }

    fn enable_selector<A, AR>(&mut self, _: A, selector: &Selector, row: usize) -> Result<(), Error>
    where
        A: FnOnce() -> AR,
        AR: Into<String>,
    {
        if row >= self.usable {
            return Err(Error::not_enough_rows_available(self.n.trailing_zeros()));
        }
        self.selectors[selector.0][row] = true;
        self.selector_region.insert((selector.0, row), self.cur);
        Ok(())
    }

    fn query_instance(&self, column: Column<Instance>, row: usize) -> Result<Value<Fp>, Error> {
        Ok(self
            .instance
            .get(column.index())
            .and_then(|c| c.get(row))
            .map(|v| Value::known(*v))
            .unwrap_or_else(Value::unknown))
    }

    fn assign_advice<V, VR, A, AR>(
        &mut self,
        annotation: A,
        column: Column<Advice>,
        row: usize,
        to: V,
    ) -> Result<(), Error>
    where
        V: FnOnce() -> Value<VR>,
        VR: Into<Assigned<Fp>>,
        A: FnOnce() -> AR,
        AR: Into<String>,
    {
        if row >= self.usable {
            return Err(Error::not_enough_rows_available(self.n.trailing_zeros()));
        }
        let (value, known) = eval_value(to());
        let name = self.path(annotation().into());
        let order = self.next();
        let region = self.cur;
        let slot = &mut self.advice[column.index()][row];
        let writes = slot.as_ref().map(|c| c.writes).unwrap_or(0) + 1;
        *slot = Some(AdviceCell { value, known, region, name, order, writes });
        Ok(())
    }

    fn assign_fixed<V, VR, A, AR>(
        &mut self,
        annotation: A,
        column: Column<Fixed>,
        row: usize,
        to: V,
    ) -> Result<(), Error>
    where
        V: FnOnce() -> Value<VR>,
        VR: Into<Assigned<Fp>>,
        A: FnOnce() -> AR,
        AR: Into<String>,
    {
        if row >= self.usable {
            return Err(Error::not_enough_rows_available(self.n.trailing_zeros()));
        }
        let (value, _) = eval_value(to());
        let name = self.path(annotation().into());
        self.fixed[column.index()][row] = Some(value);
        self.fixed_names.insert((column.index(), row), (self.cur, name));
        Ok(())
    }

    fn copy(
        &mut self,
        left_column: Column<Any>,
        left_row: usize,
        right_column: Column<Any>,
        right_row: usize,
    ) -> Result<(), Error> {
        let order = self.next();
        self.copies.push(Copy {
            left: (*left_column.column_type(), left_column.index(), left_row),
            right: (*right_column.column_type(), right_column.index(), right_row),
            region: self.cur,
            order,
        });
        Ok(())
    }

    fn fill_from_row(
        &mut self,
        column: Column<Fixed>,
        from_row: usize,
        to: Value<Assigned<Fp>>,
    ) -> Result<(), Error> {
        let (value, _) = eval_value(to);
        for row in from_row..self.usable {
            self.fixed[column.index()][row] = Some(value);
        }
        Ok(())
    }

    fn push_namespace<NR, N>(&mut self, name_fn: N)
    where
        NR: Into<String>,
        N: FnOnce() -> NR,
    {
        self.ns.push(name_fn().into());
    }

    fn pop_namespace(&mut self, _: Option<String>) {
        self.ns.pop();
    }
}

/// Field element as big-endian hex.
pub fn fp_hex(v: &Fp) -> String {
    let r = v.to_repr();
    let mut s = String::from("0x");
    for b in r.as_ref().iter().rev() {
        write!(s, "{:02x}", b).unwrap();
    }
    s
}

fn json_str(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            c if (c as u32) < 0x20 => write!(o, "\\u{:04x}", c as u32).unwrap(),
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

/// ["c",hex] ["s",sel] ["f",col,rot,qidx] ["a",col,rot,qidx] ["i",col,rot,qidx]
/// ["-",e] ["+",e,e] ["*",e,e] ["k",e,hex]
pub fn expr_json(e: &Expression<Fp>) -> String {
    match e {
        Expression::Constant(c) => format!("[\"c\",\"{}\"]", fp_hex(c)),
        Expression::Selector(s) => format!("[\"s\",{}]", s.0),
        Expression::Fixed(q) => format!("[\"f\",{},{},{}]", q.column_index, q.rotation.0, q.index),
        Expression::Advice(q) => format!("[\"a\",{},{},{}]", q.column_index, q.rotation.0, q.index),
        Expression::Instance(q) => {
            format!("[\"i\",{},{},{}]", q.column_index, q.rotation.0, q.index)
        }
        Expression::Negated(a) => format!("[\"-\",{}]", expr_json(a)),
        Expression::Sum(a, b) => format!("[\"+\",{},{}]", expr_json(a), expr_json(b)),
        Expression::Product(a, b) => format!("[\"*\",{},{}]", expr_json(a), expr_json(b)),
        Expression::Scaled(a, k) => format!("[\"k\",{},\"{}\"]", expr_json(a), fp_hex(k)),
    }
}

/// Gates, lookups, queries, permutation columns, constants columns of a constraint system.
pub fn cs_json(cs: &ConstraintSystem<Fp>) -> String {
    let mut o = String::new();
    write!(
        o,
        "{{\"num_advice\":{},\"num_fixed\":{},\"num_instance\":{},\"num_selectors\":{},\"blinding_factors\":{},\"degree\":{},",
        cs.num_advice_columns,
        cs.num_fixed_columns,
        cs.num_instance_columns,
        cs.num_selectors,
        cs.blinding_factors(),
        cs.degree()
    )
    .unwrap();
    let q = |v: Vec<(usize, i32)>| {
        v.iter().map(|(c, r)| format!("[{},{}]", c, r)).collect::<Vec<_>>().join(",")
    };
    write!(
        o,
        "\"advice_queries\":[{}],\"fixed_queries\":[{}],\"instance_queries\":[{}],",
        q(cs.advice_queries.iter().map(|(c, r)| (c.index(), r.0)).collect()),
        q(cs.fixed_queries.iter().map(|(c, r)| (c.index(), r.0)).collect()),
        q(cs.instance_queries.iter().map(|(c, r)| (c.index(), r.0)).collect())
    )
    .unwrap();
    let perm: Vec<String> = cs
        .permutation
        .get_columns()
        .iter()
        .map(|c| format!("[\"{}\",{}]", kind(c.column_type()), c.index()))
        .collect();
    write!(o, "\"permutation_columns\":[{}],", perm.join(",")).unwrap();
    let consts: Vec<String> = cs.constants.iter().map(|c| c.index().to_string()).collect();
    write!(o, "\"constants_columns\":[{}],", consts.join(",")).unwrap();
    let sm: Vec<String> = cs.selector_map.iter().map(|c| c.index().to_string()).collect();
    write!(o, "\"selector_map\":[{}],", sm.join(",")).unwrap();
    let mut gates = vec![];
    for g in cs.gates.iter() {
        let polys: Vec<String> = g
            .polynomials()
            .iter()
            .enumerate()
            .map(|(i, p)| {
                format!(
                    "{{\"name\":{},\"poly\":{}}}",
                    json_str(g.constraint_name(i)),
                    expr_json(p)
                )
            })
            .collect();
        gates.push(format!(
            "{{\"name\":{},\"constraints\":[{}]}}",
            json_str(g.name()),
            polys.join(",")
        ));
    }
    write!(o, "\"gates\":[\n{}],", gates.join(",\n")).unwrap();
    let mut lookups = vec![];
    for l in cs.lookups.iter() {
        let ins: Vec<String> = l.input_expressions.iter().map(expr_json).collect();
        let tbl: Vec<String> = l.table_expressions.iter().map(expr_json).collect();
        lookups.push(format!(
            "{{\"inputs\":[{}],\"tables\":[{}]}}",
            ins.join(","),
            tbl.join(",")
        ));
    }
    write!(o, "\"lookups\":[\n{}]}}", lookups.join(",\n")).unwrap();
    o
}

/// The recorded layout + witness as JSON.
pub fn layout_json(rec: &Recorder) -> String {
    let mut o = String::new();
    write!(o, "{{\"n\":{},\"usable_rows\":{},", rec.n, rec.usable).unwrap();
    let regs: Vec<String> = rec.regions.iter().map(|r| json_str(r)).collect();
    write!(o, "\"regions\":[\n{}],", regs.join(",\n")).unwrap();
    // advice cells: [col,row,region|-1,name,value,known,order,writes]
    let mut cells = vec![];
    for (c, col) in rec.advice.iter().enumerate() {
        for (r, cell) in col.iter().enumerate() {
            if let Some(a) = cell {
                cells.push(format!(
                    "[{},{},{},{},\"{}\",{},{},{}]",
                    c,
                    r,
                    a.region.map(|x| x as i64).unwrap_or(-1),
                    json_str(&a.name),
                    fp_hex(&a.value),
                    a.known as u8,
                    a.order,
                    a.writes
                ));
            }
        }
    }
    write!(o, "\"advice\":[\n{}],", cells.join(",\n")).unwrap();
    // fixed: [col,row,value,region|-1,name]  (only assigned cells)
    let mut fx = vec![];
    for (c, col) in rec.fixed.iter().enumerate() {
        for (r, v) in col.iter().enumerate() {
            if let Some(v) = v {
                let (reg, name) = rec
                    .fixed_names
                    .get(&(c, r))
                    .cloned()
                    .unwrap_or((None, "fill".into()));
                fx.push(format!(
                    "[{},{},\"{}\",{},{}]",
                    c,
                    r,
                    fp_hex(v),
                    reg.map(|x| x as i64).unwrap_or(-1),
                    json_str(&name)
                ));
            }
        }
    }
    write!(o, "\"fixed\":[\n{}],", fx.join(",\n")).unwrap();
    // selectors: [sel,row,region|-1]
    let mut sels = vec![];
    for (s, rows) in rec.selectors.iter().enumerate() {
        for (r, on) in rows.iter().enumerate() {
            if *on {
                let reg = rec.selector_region.get(&(s, r)).cloned().flatten();
                sels.push(format!("[{},{},{}]", s, r, reg.map(|x| x as i64).unwrap_or(-1)));
            }
        }
    }
    write!(o, "\"selectors\":[\n{}],", sels.join(",\n")).unwrap();
    let cps: Vec<String> = rec
        .copies
        .iter()
        .map(|cp| {
            format!(
                "[\"{}\",{},{},\"{}\",{},{},{},{}]",
                kind(&cp.left.0),
                cp.left.1,
                cp.left.2,
                kind(&cp.right.0),
                cp.right.1,
                cp.right.2,
                cp.region.map(|x| x as i64).unwrap_or(-1),
                cp.order
            )
        })
        .collect();
    write!(o, "\"copies\":[\n{}],", cps.join(",\n")).unwrap();
    let inst: Vec<String> = rec
        .instance
        .iter()
        .map(|c| c.iter().map(|v| format!("\"{}\"", fp_hex(v))).collect::<Vec<_>>().join(","))
        .map(|s| format!("[{}]", s))
        .collect();
    write!(o, "\"instance\":[{}]}}", inst.join(",")).unwrap();
    o
}

/// Rebuild the verifying key from the recorded fixed values, selectors and copies, the way
/// `keygen_vk` does, and return its pinned representation (Debug string).
pub fn rebuild_vk_pinned(
    params: &Params<vesta::Affine>,
    cs: &ConstraintSystem<Fp>,
    rec: &Recorder,
) -> String {
    let domain = EvaluationDomain::new(cs.degree() as u32, params.k);
    let mut fixed = vec![domain.empty_lagrange_assigned(); cs.num_fixed_columns];
    for (c, col) in rec.fixed.iter().enumerate() {
        for (r, v) in col.iter().enumerate() {
            if let Some(v) = v {
                fixed[c][r] = Assigned::Trivial(*v);
            }
        }
    }
    let mut fixed = batch_invert_assigned(fixed);
    let (cs2, selector_polys) = cs.clone().compress_selectors(rec.selectors.clone());
    fixed.extend(selector_polys.into_iter().map(|p| domain.lagrange_from_vec(p)));
    let mut perm = permutation::keygen::Assembly::new(params.n as usize, &cs2.permutation);
    let pcols = cs2.permutation.get_columns();
    for cp in rec.copies.iter() {
        let col = |k: Any, i: usize| -> Column<Any> {
            *pcols
                .iter()
                .find(|c| *c.column_type() == k && c.index() == i)
                .expect("copy on a column without equality enabled")
        };
        perm.copy(col(cp.left.0, cp.left.1), cp.left.2, col(cp.right.0, cp.right.1), cp.right.2)
            .expect("copy on a permutation column");
    }
    let pvk = perm.build_vk(params, &domain, &cs2.permutation);
    let fc: Vec<vesta::Affine> = fixed
        .iter()
        .map(|p| params.commit_lagrange(p, Blind::default()).to_affine_vartime())
        .collect();
    let vk = VerifyingKey::from_parts(domain, fc, pvk, cs2);
    format!("{:?}", vk.pinned())
}

/// The pinned representation and the (compressed) constraint system of a real VK.
pub fn vk_pinned(vk: &VerifyingKey<vesta::Affine>) -> String {
    format!("{:?}", vk.pinned())
}

pub fn vk_cs(vk: &VerifyingKey<vesta::Affine>) -> &ConstraintSystem<Fp> {
    &vk.cs
}

#[allow(unused)]
fn _assert_curve<C: CurveAffine>() {}

/// Configure `C` and synthesize it once through a `Recorder` (same call keygen makes).
pub fn record<C: super::Circuit<Fp>>(
    circuit: &C,
    k: u32,
    instance: Vec<Vec<Fp>>,
) -> Result<(ConstraintSystem<Fp>, Recorder), Error> {
    use super::FloorPlanner;
    let mut cs = ConstraintSystem::default();
    let config = C::configure(&mut cs);
    let mut rec = Recorder::new(&cs, k, instance);
    C::FloorPlanner::synthesize(&mut rec, circuit, config, cs.constants.clone())?;
    Ok((cs, rec))
}

fn words(bytes: &[u8]) -> String {
    (0..8)
        .map(|i| u32::from_le_bytes(bytes[4 * i..4 * i + 4].try_into().unwrap()).to_string())
        .collect::<Vec<_>>()
        .join(", ")
}

/// The transcript-relevant parts of a VK: transcript_repr (the BLAKE2b digest of the pinned
/// VK, absorbed into every proof's transcript), its fixed and permutation commitments
/// (affine x, y as the eight little-endian u32 words of their canonical repr, the format
/// of halo2/verifier's generated `V.Aff{Fq.from_words(...), ...}` literals).
pub fn vk_digest_json(vk: &VerifyingKey<vesta::Affine>) -> String {
    let pt = |p: &vesta::Affine| {
        let c = p.coordinates().unwrap();
        format!("[\"{}\",\"{}\"]", words(c.x().to_repr().as_ref()), words(c.y().to_repr().as_ref()))
    };
    let fixed: Vec<String> = vk.fixed_commitments.iter().map(pt).collect();
    let perm: Vec<String> = vk.permutation.commitments().iter().map(pt).collect();
    format!(
        "{{\"transcript_repr\":\"{}\",\"fixed_commitments\":[{}],\"permutation_commitments\":[{}]}}",
        fp_hex(&vk.transcript_repr),
        fixed.join(","),
        perm.join(",")
    )
}
