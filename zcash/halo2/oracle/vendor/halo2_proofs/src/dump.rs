//! ORACLE PATCH: records every intermediate value of proof verification, in order,
//! so an independent implementation (the Bend verifier) can be checked stage by stage.
use std::cell::RefCell;

use group::ff::PrimeField;
use group::GroupEncoding;

thread_local! {
    static LOG: RefCell<Option<Vec<(String, Vec<u8>)>>> = const { RefCell::new(None) };
}

/// Starts recording on this thread (clearing any previous log).
pub fn start() {
    LOG.with(|l| *l.borrow_mut() = Some(Vec::new()));
}

/// Stops recording and returns the log.
pub fn take() -> Vec<(String, Vec<u8>)> {
    LOG.with(|l| l.borrow_mut().take().unwrap_or_default())
}

/// Records a named byte string.
pub fn rec(name: impl Into<String>, bytes: impl AsRef<[u8]>) {
    LOG.with(|l| {
        if let Some(v) = l.borrow_mut().as_mut() {
            v.push((name.into(), bytes.as_ref().to_vec()));
        }
    });
}

/// Whether recording is active on this thread.
pub fn enabled() -> bool {
    LOG.with(|l| l.borrow().is_some())
}

/// Records a field element (canonical little-endian repr).
pub fn scalar<F: PrimeField>(name: impl Into<String>, f: &F) {
    if enabled() {
        rec(name, f.to_repr().as_ref());
    }
}

/// Records a point (compressed encoding).
pub fn point<G: GroupEncoding>(name: impl Into<String>, p: &G) {
    if enabled() {
        rec(name, p.to_bytes().as_ref());
    }
}
