// Runs the Bend-compiled Halo 2 verifier off the main thread.
import { paramsList, verifyBundle } from "./zebend.mjs";

let params = null;

self.onmessage = async ({ data }) => {
  const { id, url, tamper } = data;
  try {
    if (!params) {
      const g = new Uint8Array(await (await fetch("data/params_g.bin")).arrayBuffer());
      params = paramsList(g);
    }
    const bytes = new Uint8Array(await (await fetch(url)).arrayBuffer());
    if (tamper) {
      // Flip one bit in the middle of the proof bytes (header: np, ni, proof byte length).
      const proofLen = new DataView(bytes.buffer).getUint32(8, true);
      bytes[12 + (proofLen >>> 1) + 3] ^= 0x01;
    }
    const t = performance.now();
    const ok = verifyBundle(params, bytes);
    self.postMessage({ id, ok, ms: performance.now() - t });
  } catch (e) {
    self.postMessage({ id, error: String(e) });
  }
};
