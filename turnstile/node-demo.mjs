// Calls the Bend-compiled turnstile (pools.mjs) from plain JavaScript.
// Constructors cross as {$: "Name", field: value}; Nat crosses as a number.
import P from "./pools.mjs";

const ZEC = 10_000_000; // model unit = 10 zatoshi
const F = (inp, out) => ({ $: "Flow", inp, out });
const none = F(0, 0);
const pools = { $: "Pools", t: 100 * ZEC, sp: 0, sa: 0, orc: 0, iw: 40 * ZEC };
const tx = (iwOut) => ({ $: "Tx", t: F(iwOut, 0), sp: none, sa: none, orc: none, iw: F(0, iwOut), issue: 0, burn: 0 });
const era = { $: "NU63" };

for (const out of [40 * ZEC, 41 * ZEC]) {
  const r = P.apply(era, pools, tx(out));
  console.log(`unshield ${out / ZEC} ZEC from an Ironwood pool holding 40 ZEC ->`,
    r.$ === "Some" ? `accepted, ironwood now ${P["Pools.iw"](r.value) / ZEC} ZEC` : "REJECTED (turnstile)");
}
