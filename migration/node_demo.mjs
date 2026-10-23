// Calls the Bend-compiled, law-checked planner from plain Node.js.
import Planner from "./planner.mjs";

const list = (xs) => xs.reduceRight((tail, head) => ({ $: "Con", head, tail }), { $: "Nil" });
const note = (zat) => ({ $: "Note", pool: { $: "Orchard" }, value: zat });

console.log(Planner["run"](list([note(400000000)]), 314159265));
console.log("fee for 1 spend, 15 outputs:", Planner["planner:zip317_fee"](1, 15));
