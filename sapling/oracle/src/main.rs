//! sapling-oracle: Rust ground truth for Zebend's Sapling work. See ../README.md.

mod chain;
mod ctxset;
mod lwd;
mod sigs;
mod txs;
mod txutil;
mod vectors;

use anyhow::{anyhow, Result};

pub const DATA: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../data");
pub const SAPLING_ACTIVATION: u64 = 419_200;

#[tokio::main]
async fn main() -> Result<()> {
    let a: Vec<String> = std::env::args().collect();
    let arg = |i: usize| a.get(i).map(|s| s.parse::<u64>()).transpose();
    std::fs::create_dir_all(DATA)?;
    match a.get(1).map(String::as_str) {
        Some("meta") => chain::meta(arg(2)?.unwrap()).await,
        Some("sync") => chain::sync(arg(2)?.unwrap_or(SAPLING_ACTIVATION), arg(3)?.unwrap_or(3_528_268), arg(4)?.unwrap_or(6) as usize).await,
        Some("subtrees") => chain::subtrees().await,
        Some("trees") => chain::trees(&a[2..].iter().map(|s| s.parse()).collect::<Result<Vec<u64>, _>>()?).await,
        Some("rebuild") => chain::rebuild(),
        Some("vectors") => vectors::run(arg(2)?.unwrap_or(2026)),
        Some("scan") => sigs::scan(arg(2)?.unwrap(), arg(3)?.unwrap(), arg(4)?.unwrap_or(1000), arg(5)?.unwrap_or(1000)).await,
        Some("fetch") => sigs::fetch("sig_txids.txt", "sig_raw.bin", arg(2)?.unwrap_or(16) as usize).await,
        Some("build") => sigs::build(arg(2)?.unwrap_or(u64::MAX) as usize),
        Some("tamper") => sigs::tamper(
            arg(2)?.unwrap() as usize,
            &a[3],
            arg(4)?.unwrap() as usize,
            arg(5)?.map(|x| x as usize),
            arg(6)?.map(|x| x as u8),
        ),
        Some("tampermix") => sigs::tampermix(arg(2)?.unwrap_or(4) as usize, arg(3)?.unwrap_or(2026)),
        Some("txs") => txs::txs(arg(2)?.unwrap_or(200) as usize).await,
        Some("parsetime") => txutil::parsetime(arg(2)?.unwrap_or(1) as usize),
        Some("ctxset") => ctxset::ctxset().await,
        Some("rust") => sigs::rust(arg(2)?.unwrap_or(1) as usize),
        _ => Err(anyhow!(
            "usage: meta H | sync FROM TO [WORKERS] | subtrees | trees H.. | rebuild | vectors [SEED] | scan FROM TO WINDOW STRIDE | fetch [CONC] | build [MAXSIGS] | tamper K FIELD I [BYTE] [MASK] | tampermix [N] [SEED] | rust THREADS | txs"
        )),
    }
}
