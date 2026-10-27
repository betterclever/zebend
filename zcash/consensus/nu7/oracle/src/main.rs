//! nu7-oracle: differential-test oracle for Zcash NU7, using ONLY Zebra's public zebra-chain API
//! at commit 1e03ee753fbc72d70882cdfd3c8bdd58b80f0f97 (plus the verbatim copy of zebra-state's
//! `AdjustedDifficulty` in `difficulty.rs`).
//!
//! Sources (paths under data/src/zebra):
//!   zebra-chain/src/parameters/network/subsidy.rs  (halving:468, scheduled_block_subsidy:908,
//!     funding_stream_values:450, funding_stream_address:392, funding_stream_address_period:314,
//!     nsm_fee_contribution:733, additional_block_subsidy:835,
//!     block_subsidy_with_parent_nsm_value_balance:872, cumulative_scheduled_issuance:954)
//!   zebra-chain/src/parameters/network_upgrade.rs  (target_spacing:449, averaging_window:590,
//!     minimum_difficulty_spacing_for_height:530, is_testnet_min_difficulty_block:569)
//!   zebra-state/src/service/check/difficulty.rs     (AdjustedDifficulty, copied)
//!
//! CLI (stdin -> one JSON object per line on stdout; amounts are decimal strings).
//! <net> is mainnet, testnet, or (for Zakura cross-checks) testnet@NU7HEIGHT / regtest@NU7HEIGHT:
//!   nu7-oracle heights  <mainnet|testnet>   stdin: "height"
//!   nu7-oracle fees     <net>               stdin: "height fees"
//!   nu7-oracle nsm      <net>               stdin: "height parent_nsm_balance"
//!   nu7-oracle consts   <net>
//!   nu7-oracle boundaries <net>             funding-stream address-period change heights
//!   nu7-oracle diffchain <net>              stdin: "height time bits|?"
//!   nu7-oracle headers  <net> <first_height> <file of raw 1487-byte headers>

mod difficulty;

use std::{
    collections::BTreeMap,
    io::{BufRead, Write},
    panic::{catch_unwind, AssertUnwindSafe},
};

use chrono::{DateTime, TimeZone, Utc};
use serde_json::{json, Value};
use zebra_chain::{
    amount::{Amount, NonNegative},
    block::Height,
    parameters::{
        subsidy::{self, FundingStreamReceiver, ParameterSubsidy as _},
        ConsensusBranchId, Network, NetworkUpgrade,
    },
    work::difficulty::CompactDifficulty,
};

use difficulty::{pow_adjustment_block_span, AdjustedDifficulty, MAX_POW_ADJUSTMENT_BLOCK_SPAN};

const RECEIVERS: [FundingStreamReceiver; 4] = [
    FundingStreamReceiver::Ecc,
    FundingStreamReceiver::ZcashFoundation,
    FundingStreamReceiver::MajorGrants,
    FundingStreamReceiver::Deferred,
];

/// Runs `f`, turning a panic into an "ERR:panic:..." string value.
fn g(f: impl FnOnce() -> Value) -> Value {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|e| {
        let m = e
            .downcast_ref::<String>()
            .cloned()
            .or_else(|| e.downcast_ref::<&str>().map(|s| s.to_string()))
            .unwrap_or_default();
        Value::String(format!("ERR:panic:{m}"))
    })
}

fn amt(a: Amount<NonNegative>) -> Value {
    Value::String(u64::from(a).to_string())
}

fn err(e: impl std::fmt::Display) -> Value {
    Value::String(format!("ERR:{e}"))
}

fn res<T, E: std::fmt::Display>(r: Result<T, E>, f: impl FnOnce(T) -> Value) -> Value {
    match r {
        Ok(v) => f(v),
        Err(e) => err(e),
    }
}

fn rname(r: FundingStreamReceiver) -> String {
    format!("{r:?}")
}

/// `mainnet`, `testnet`, plus two configured networks built the same way as Zakura's dump
/// (zakura-consensus/tests/nu7_diff_dump.rs build_testnet/build_regtest), for cross-checks:
/// `testnet@N` = public Testnet with NU7 moved to N; `regtest@N` = Regtest with every upgrade
/// through NU6.3 at 1 and NU7 at N.
fn network(name: &str) -> Network {
    use zebra_chain::parameters::testnet::{self, ConfiguredActivationHeights, RegtestParameters};
    match name.split_once('@') {
        None if name == "mainnet" => Network::Mainnet,
        None if name == "testnet" => Network::new_default_testnet(),
        Some(("testnet", n)) => {
            let def = Network::new_default_testnet();
            let mut h = ConfiguredActivationHeights::default();
            for (height, nu) in def.activation_list() {
                let v = Some(height.0);
                match nu {
                    NetworkUpgrade::Genesis => {}
                    NetworkUpgrade::BeforeOverwinter => h.before_overwinter = v,
                    NetworkUpgrade::Overwinter => h.overwinter = v,
                    NetworkUpgrade::Sapling => h.sapling = v,
                    NetworkUpgrade::Blossom => h.blossom = v,
                    NetworkUpgrade::Heartwood => h.heartwood = v,
                    NetworkUpgrade::Canopy => h.canopy = v,
                    NetworkUpgrade::Nu5 => h.nu5 = v,
                    NetworkUpgrade::Nu6 => h.nu6 = v,
                    NetworkUpgrade::Nu6_1 => h.nu6_1 = v,
                    NetworkUpgrade::Nu6_2 => h.nu6_2 = v,
                    NetworkUpgrade::Nu6_3 => h.nu6_3 = v,
                    NetworkUpgrade::Nu7 => h.nu7 = v,
                }
            }
            h.nu7 = Some(n.parse().expect("NU7 height"));
            testnet::Parameters::build()
                .with_activation_heights(h)
                .expect("activation heights")
                .to_network()
                .expect("configured testnet")
        }
        Some(("regtest", n)) => {
            let one = Some(1);
            Network::new_regtest(RegtestParameters {
                activation_heights: ConfiguredActivationHeights {
                    before_overwinter: one, overwinter: one, sapling: one, blossom: one,
                    heartwood: one, canopy: one, nu5: one, nu6: one, nu6_1: one, nu6_2: one,
                    nu6_3: one, nu7: Some(n.parse().expect("NU7 height")),
                },
                ..Default::default()
            })
        }
        _ => panic!("network must be mainnet, testnet, testnet@N or regtest@N"),
    }
}

fn hex_compact(c: CompactDifficulty) -> String {
    hex::encode(c.bytes_in_display_order())
}

fn compact_from_u32(v: u32) -> Option<CompactDifficulty> {
    CompactDifficulty::from_bytes_in_display_order(&v.to_be_bytes()).ok()
}

fn dt(t: i64) -> DateTime<Utc> {
    Utc.timestamp_opt(t, 0).single().expect("valid timestamp")
}

fn amount(v: u64) -> Result<Amount<NonNegative>, String> {
    Amount::try_from(v).map_err(|e| e.to_string())
}

/// funding_stream_values -> {receiver: value}, only the receivers Zebra returns.
fn fs_map(h: Height, net: &Network, s: Amount<NonNegative>) -> Value {
    res(subsidy::funding_stream_values(h, net, s), |m| {
        let m: BTreeMap<String, Value> = m.into_iter().map(|(r, a)| (rname(r), amt(a))).collect();
        json!(m)
    })
}

fn cmd_heights(net: &Network, lines: Vec<String>, out: &mut impl Write) {
    for l in lines {
        let Ok(h) = l.trim().parse::<u32>() else { continue };
        let h = Height(h);
        let sched = catch_unwind(AssertUnwindSafe(|| subsidy::scheduled_block_subsidy(h, net)));
        let sched: Result<Amount<NonNegative>, String> = match sched {
            Ok(Ok(s)) => Ok(s),
            Ok(Err(e)) => Err(format!("ERR:{e}")),
            Err(_) => Err("ERR:panic".into()),
        };
        let with_sched = |f: &dyn Fn(Amount<NonNegative>) -> Value| match &sched {
            Ok(s) => g(|| f(*s)),
            Err(e) => Value::String(e.clone()),
        };
        let mut script = serde_json::Map::new();
        let mut addr = serde_json::Map::new();
        for r in RECEIVERS {
            let a = catch_unwind(AssertUnwindSafe(|| {
                subsidy::funding_stream_address(h, net, r).cloned()
            }));
            let (s, t) = match a {
                Ok(Some(a)) => (
                    Value::String(hex::encode(a.script().as_raw_bytes())),
                    Value::String(a.to_string()),
                ),
                Ok(None) => (Value::Null, Value::Null),
                Err(_) => (json!("ERR:panic"), json!("ERR:panic")),
            };
            script.insert(rname(r), s);
            addr.insert(rname(r), t);
        }
        let o = json!({
            "h": h.0,
            "nu": g(|| json!(NetworkUpgrade::current(net, h).to_string())),
            "branch_id": g(|| match ConsensusBranchId::current(net, h) {
                Some(b) => json!(format!("0x{:08x}", u32::from(b))),
                None => Value::Null,
            }),
            "target_spacing": g(|| json!(NetworkUpgrade::target_spacing_for_height(net, h).num_seconds())),
            "averaging_window": g(|| json!(NetworkUpgrade::averaging_window_for_height(net, h))),
            "halving": g(|| json!(subsidy::halving(h, net))),
            "scheduled_block_subsidy": match &sched { Ok(s) => amt(*s), Err(e) => json!(e) },
            "fs": with_sched(&|s| fs_map(h, net, s)),
            "fs_script": script,
            "fs_addr": addr,
            "miner_subsidy": with_sched(&|s| res(subsidy::miner_subsidy(h, net, s), amt)),
            "founders_reward": g(|| amt(subsidy::founders_reward(net, h))),
            "address_period": g(|| json!(subsidy::funding_stream_address_period(h, net))),
            "nsm_tracked": g(|| json!(subsidy::nsm_value_balance_is_tracked(h, net))),
            "nsm_reissuance_active": g(|| json!(subsidy::nsm_reissuance_is_active(h, net))),
            "min_difficulty_gap": g(|| match NetworkUpgrade::minimum_difficulty_spacing_for_height(net, h) {
                Some(d) => json!(d.num_seconds()),
                None => Value::Null,
            }),
        });
        writeln!(out, "{o}").unwrap();
    }
}

fn cmd_fees(net: &Network, lines: Vec<String>, out: &mut impl Write) {
    for l in lines {
        let p: Vec<u64> = l.split_whitespace().filter_map(|x| x.parse().ok()).collect();
        let [h, f] = p[..] else { continue };
        let h = Height(h as u32);
        let o = match amount(f) {
            Err(e) => json!({"h": h.0, "fees": f.to_string(), "contribution": err(&e), "miner": err(&e)}),
            Ok(fa) => {
                let c = g(|| amt(subsidy::nsm_fee_contribution(h, net, fa)));
                let miner = match c.as_str().and_then(|s| s.parse::<u64>().ok()) {
                    Some(c) => json!((f - c).to_string()),
                    None => c.clone(),
                };
                json!({"h": h.0, "fees": f.to_string(), "contribution": c, "miner": miner})
            }
        };
        writeln!(out, "{o}").unwrap();
    }
}

fn cmd_nsm(net: &Network, lines: Vec<String>, out: &mut impl Write) {
    for l in lines {
        let p: Vec<u64> = l.split_whitespace().filter_map(|x| x.parse().ok()).collect();
        let [h, b] = p[..] else { continue };
        let h = Height(h as u32);
        let o = match amount(b) {
            Err(e) => json!({"h": h.0, "balance": b.to_string(), "additional": err(&e), "subsidy_with_parent": err(&e)}),
            Ok(ba) => {
                // `additional_block_subsidy` takes NSMValueBalance(h-1) directly (no seed added);
                // `block_subsidy_with_parent_nsm_value_balance` takes the parent balance and adds
                // INITIAL_NSM_VALUE_BALANCE at the NU7 activation block (subsidy.rs:788,872).
                let swp = catch_unwind(AssertUnwindSafe(|| {
                    subsidy::block_subsidy_with_parent_nsm_value_balance(h, net, ba)
                }));
                let (swp_v, fs, miner) = match swp {
                    Ok(Ok(s)) => (
                        amt(s),
                        g(|| fs_map(h, net, s)),
                        g(|| res(subsidy::miner_subsidy(h, net, s), amt)),
                    ),
                    Ok(Err(e)) => (err(&e), err(&e), err(&e)),
                    Err(_) => (json!("ERR:panic"), json!("ERR:panic"), json!("ERR:panic")),
                };
                json!({
                    "h": h.0, "balance": b.to_string(),
                    "additional": g(|| amt(subsidy::additional_block_subsidy(h, net, ba))),
                    "balance_before": g(|| amt(subsidy::nsm_value_balance_before(h, net, ba))),
                    "subsidy_with_parent": swp_v,
                    // What Zebra's coinbase check uses: fs values of the TOTAL subsidy
                    // (zebra-state/src/service/check.rs:441 -> subsidy/check.rs:146).
                    "fs_with_parent": fs,
                    "miner_subsidy_with_parent": miner,
                })
            }
        };
        writeln!(out, "{o}").unwrap();
    }
}

fn cmd_consts(net: &Network, out: &mut impl Write) {
    let a = NetworkUpgrade::Nu7.activation_height(net).expect("NU7 scheduled");
    let opt_h = |h: Option<Height>| h.map_or(Value::Null, |h| json!(h.0));
    let halvings: Vec<Value> = (1..=6).map(|i| g(|| opt_h(subsidy::height_for_halving(i, net)))).collect();
    let third = subsidy::height_for_halving(3, net);
    let reiss = net.nsm_reissuance_height();
    let streams: Vec<Value> = net
        .all_funding_streams()
        .iter()
        .map(|fs| {
            let rec: BTreeMap<String, Value> = fs
                .recipients()
                .iter()
                .map(|(r, v)| (rname(*r), json!({"numerator": v.numerator(), "n_addresses": v.addresses().len()})))
                .collect();
            json!({"start": fs.height_range().start.0, "end": fs.height_range().end.0, "recipients": rec})
        })
        .collect();
    let mut cum = serde_json::Map::new();
    let mut cum_hs = vec![a.0 - 1, 10_000_000, 50_000_000];
    if let Some(t) = third { cum_hs.push(t.0); }
    if let Some(r) = reiss { cum_hs.push(r.0); cum_hs.push(r.0 - 1); }
    cum_hs.sort();
    for h in cum_hs {
        cum.insert(h.to_string(), g(|| res(subsidy::cumulative_scheduled_issuance(Height(h), net), amt)));
    }
    let acts: BTreeMap<String, u32> = net.activation_list().into_iter().map(|(h, nu)| (nu.to_string(), h.0)).collect();
    let o = json!({
        "nu7_activation": a.0,
        "activation_heights": acts,
        "nsm_reissuance_height": opt_h(reiss),
        "initial_nsm_value_balance": amt(net.initial_nsm_value_balance()),
        "height_for_halving_1_to_6": halvings,
        "funding_streams": streams,
        "post_blossom_halving_interval": net.post_blossom_halving_interval(),
        "post_nu7_halving_interval": net.post_nu7_halving_interval(),
        "funding_stream_address_change_interval": net.funding_stream_address_change_interval(),
        "LN2_SCALED": subsidy::LN2_SCALED.to_string(),
        "BLOCK_SUBSIDY_FRACTION_DENOMINATOR": subsidy::BLOCK_SUBSIDY_FRACTION_DENOMINATOR.to_string(),
        "block_subsidy_fraction_numerator_pre_nu7": subsidy::block_subsidy_fraction_numerator(Height(a.0 - 1), net),
        "block_subsidy_fraction_numerator_post_nu7": subsidy::block_subsidy_fraction_numerator(a, net),
        "cumulative_scheduled_issuance": cum,
    });
    writeln!(out, "{o}").unwrap();
}

/// Heights in each funding stream range where `funding_stream_address_period` changes
/// (linear scan; the first height of each range is not listed).
fn cmd_boundaries(net: &Network, out: &mut impl Write) {
    for fs in net.all_funding_streams() {
        let r = fs.height_range();
        let mut v = Vec::new();
        let mut prev = subsidy::funding_stream_address_period(r.start, net);
        for h in r.start.0 + 1..r.end.0 {
            let p = subsidy::funding_stream_address_period(Height(h), net);
            if p != prev { v.push(h); prev = p; }
        }
        writeln!(out, "{}", json!({"start": r.start.0, "end": r.end.0, "boundaries": v})).unwrap();
    }
}

/// One chain entry: (height, time, bits).
type Entry = (u32, i64, CompactDifficulty);

/// Computes Zebra's expected threshold for a candidate at (h, t) after `chain`, passing the
/// previous up-to-MAX_POW_ADJUSTMENT_BLOCK_SPAN (bits, time) in reverse height order, as
/// zebra-state does; `AdjustedDifficulty::new_from_header_time` then takes the span it needs.
fn expected(net: &Network, chain: &[Entry], h: u32, t: i64) -> Result<(CompactDifficulty, i64, bool), String> {
    catch_unwind(AssertUnwindSafe(|| {
        let ctx: Vec<_> = chain.iter().rev().take(MAX_POW_ADJUSTMENT_BLOCK_SPAN).map(|e| (e.2, dt(e.1))).collect();
        let prev_t = chain.last().expect("non-empty").1;
        let adj = AdjustedDifficulty::new_from_header_time(dt(t), Height(h - 1), net, ctx);
        let min = NetworkUpgrade::is_testnet_min_difficulty_block(net, Height(h), dt(t), dt(prev_t));
        (adj.expected_difficulty_threshold(), adj.median_time_past().timestamp(), min)
    }))
    .map_err(|e| {
        format!("ERR:panic:{}", e.downcast_ref::<String>().cloned().or_else(|| e.downcast_ref::<&str>().map(|s| s.to_string())).unwrap_or_default())
    })
}

fn cmd_diffchain(net: &Network, lines: Vec<String>, out: &mut impl Write) {
    let mut chain: Vec<Entry> = Vec::new();
    for l in lines {
        let p: Vec<&str> = l.split_whitespace().collect();
        if p.len() != 3 { continue; }
        let (h, t): (u32, i64) = (p[0].parse().unwrap(), p[1].parse().unwrap());
        let given = (p[2] != "?").then(|| {
            let v = u32::from_str_radix(p[2].trim_start_matches("0x"), 16).expect("hex bits");
            compact_from_u32(v).expect("valid compact bits")
        });
        if chain.is_empty() {
            chain.push((h, t, given.expect("the first line must give bits")));
            continue;
        }
        let e = expected(net, &chain, h, t);
        let o = match &e {
            Ok((x, mtp, min)) => json!({
                "h": h, "time": t, "expected": hex_compact(*x),
                "given": given.map(hex_compact), "mtp": mtp, "min_diff": min,
                "match": given.map(|gv| gv == *x),
            }),
            Err(s) => json!({"h": h, "time": t, "expected": s, "given": given.map(hex_compact)}),
        };
        writeln!(out, "{o}").unwrap();
        let bits = given.or(e.ok().map(|x| x.0)).expect("bits for chain context");
        chain.push((h, t, bits));
    }
}

fn cmd_headers(net: &Network, first: u32, path: &str, out: &mut impl Write) {
    let data = std::fs::read(path).expect("read header file");
    assert!(data.len() % 1487 == 0, "file length is not a multiple of 1487");
    let mut chain: Vec<Entry> = Vec::new();
    let (mut checked, mut mism) = (0u64, 0u64);
    for (i, hd) in data.chunks(1487).enumerate() {
        let h = first + i as u32;
        let t = u32::from_le_bytes(hd[100..104].try_into().unwrap()) as i64;
        let bits_v = u32::from_le_bytes(hd[104..108].try_into().unwrap());
        let bits = compact_from_u32(bits_v).expect("valid header bits");
        if chain.len() >= pow_adjustment_block_span(net, Height(h)) {
            let e = expected(net, &chain, h, t);
            let (x, m) = match &e {
                Ok((x, _, _)) => (hex_compact(*x), *x == bits),
                Err(s) => (s.clone(), false),
            };
            checked += 1;
            if !m { mism += 1; }
            writeln!(out, "{}", json!({"h": h, "expected": x, "given": hex_compact(bits), "match": m})).unwrap();
        }
        chain.push((h, t, bits));
        if chain.len() > 2 * MAX_POW_ADJUSTMENT_BLOCK_SPAN { chain.drain(..MAX_POW_ADJUSTMENT_BLOCK_SPAN); }
    }
    writeln!(out, "{}", json!({"summary": if mism == 0 {"ok"} else {"mismatch"}, "checked": checked, "mismatches": mism})).unwrap();
}

fn main() {
    std::panic::set_hook(Box::new(|_| {}));
    let args: Vec<String> = std::env::args().collect();
    let usage = "usage: nu7-oracle <heights|fees|nsm|consts|boundaries|diffchain|headers> <mainnet|testnet> [first_height file]";
    if args.len() < 3 { eprintln!("{usage}"); std::process::exit(2); }
    let net = network(&args[2]);
    let stdout = std::io::stdout();
    let mut out = std::io::BufWriter::new(stdout.lock());
    let read = || std::io::stdin().lock().lines().map(|l| l.unwrap()).filter(|l| !l.trim().is_empty()).collect::<Vec<_>>();
    match args[1].as_str() {
        "heights" => cmd_heights(&net, read(), &mut out),
        "fees" => cmd_fees(&net, read(), &mut out),
        "nsm" => cmd_nsm(&net, read(), &mut out),
        "consts" => cmd_consts(&net, &mut out),
        "boundaries" => cmd_boundaries(&net, &mut out),
        "diffchain" => cmd_diffchain(&net, read(), &mut out),
        "headers" => cmd_headers(&net, args[3].parse().expect("first_height"), &args[4], &mut out),
        _ => { eprintln!("{usage}"); std::process::exit(2); }
    }
}
