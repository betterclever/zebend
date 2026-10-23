// Verifies a real mainnet Orchard/Ironwood Halo 2 proof with the Bend-compiled JS module.
import { readFileSync } from "node:fs";
import { paramsList, verifyBundle } from "../zebend.mjs";
const [gPath, ...bundles] = process.argv.slice(2);
const params = paramsList(readFileSync(gPath));
for (const b of bundles) {
  const t = performance.now();
  const ok = verifyBundle(params, readFileSync(b));
  console.log(`${b}: ${ok ? "VALID" : "INVALID"}  (${((performance.now() - t) / 1000).toFixed(2)} s)`);
}
