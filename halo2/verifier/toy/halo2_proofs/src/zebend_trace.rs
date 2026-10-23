//! Zebend oracle hooks: records every verifier intermediate as `name hex` lines
//! (canonical little-endian bytes, as in halo2-bend/CONTRACT.md).
use std::cell::RefCell;

use group::ff::PrimeField;

thread_local! {
    static TRACE: RefCell<Vec<(String, String)>> = const { RefCell::new(Vec::new()) };
}

/// Records a field element.
pub fn f<F: PrimeField>(name: impl Into<String>, v: &F) {
    raw(name, v.to_repr().as_ref());
}

/// Records raw bytes.
pub fn raw(name: impl Into<String>, bytes: &[u8]) {
    let name = name.into();
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    TRACE.with(|t| t.borrow_mut().push((name, hex)));
}

/// Takes and clears the recorded trace.
pub fn take() -> Vec<(String, String)> {
    TRACE.with(|t| std::mem::take(&mut *t.borrow_mut()))
}
