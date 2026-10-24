//! Prints the post-NU6.3 Orchard circuit's gate names and constraint names, in the
//! order halo2 stores them in the VerifyingKey (the order halo2/gen/orchard_cs.bend's
//! gate_<g>_<p> defs follow). Gate names are crate-private in halo2_proofs, so they
//! are read from the VerifyingKey's Debug output.
use orchard::circuit::{OrchardCircuitVersion, VerifyingKey};

fn main() {
    let vk = VerifyingKey::build(OrchardCircuitVersion::PostNu6_3);
    let dbg = format!("{:?}", vk.oracle_vk());
    let mut g = 0;
    let mut rest = dbg.as_str();
    while let Some(i) = rest.find("Gate { name: \"") {
        rest = &rest[i + 14..];
        let end = rest.find('"').unwrap();
        let name = &rest[..end];
        let cn_start = rest.find("constraint_names: [").unwrap() + 19;
        let cn_end = cn_start + rest[cn_start..].find(']').unwrap();
        println!("gate {g}: {name} | constraints: [{}]", &rest[cn_start..cn_end]);
        g += 1;
    }
}
