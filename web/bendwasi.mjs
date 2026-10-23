// Runs a Bend program compiled with bend2wasm, in the browser or Node,
// with in-memory input files under /data and captured stdout.
import { WASI, File, OpenFile, PreopenDirectory, ConsoleStdout } from "./vendor/shim/dist/index.js";

export async function runBend(wasmBytes, files = {}, args = []) {
  let out = "";
  const dec = new TextDecoder();
  const data = new Map(Object.entries(files).map(([name, bytes]) => [name, new File(bytes)]));
  const fds = [
    new OpenFile(new File([])),
    new ConsoleStdout((b) => { out += dec.decode(b, { stream: true }); }),
    new ConsoleStdout((b) => { out += dec.decode(b, { stream: true }); }),
    new PreopenDirectory("/data", data),
  ];
  const wasi = new WASI(["bend", ...args], [], fds);
  const { instance } = await WebAssembly.instantiate(wasmBytes, { wasi_snapshot_preview1: wasi.wasiImport });
  const t0 = performance.now();
  let code = 0;
  try { code = wasi.start(instance); } catch (e) { out += `\n[trap] ${e}`; code = -1; }
  return { out, code, ms: performance.now() - t0 };
}
