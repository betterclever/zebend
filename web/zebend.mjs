// Browser/Node glue for the Bend-compiled Halo 2 verifier (verify.mjs).
import V from "./verify.mjs";

const NIL = { $: "Nil" };
const cons = (head, tail) => ({ $: "Con", head, tail });

function u32words(bytes) {
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const out = new Array(bytes.byteLength >>> 2);
  for (let i = 0; i < out.length; i++) out[i] = dv.getUint32(4 * i, true);
  return out;
}

function list(xs) {
  let l = NIL;
  for (let i = xs.length - 1; i >= 0; i--) l = cons(xs[i], l);
  return l;
}

// params_g.bin: 2048 compressed Vesta points of 32 bytes -> List<W{w0..w7}>
export function paramsList(gBytes) {
  const ws = u32words(gBytes);
  const pts = [];
  for (let i = 0; i < ws.length; i += 8) {
    pts.push({ $: "W", w0: ws[i], w1: ws[i + 1], w2: ws[i + 2], w3: ws[i + 3], w4: ws[i + 4], w5: ws[i + 5], w6: ws[i + 6], w7: ws[i + 7] });
  }
  return list(pts);
}

// Returns true if the bundle's Halo 2 proof verifies (post-NU6.3 Orchard/Ironwood circuit).
export function verifyBundle(params, bundleBytes) {
  return V["verify_w"](params, list(u32words(bundleBytes))) === 1;
}
