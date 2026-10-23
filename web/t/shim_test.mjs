import { readFileSync } from "node:fs";
import { runBend } from "../bendwasi.mjs";
const r = await runBend(readFileSync(new URL("./readsum.wasm", import.meta.url)), { "input.bin": new Uint8Array([1, 2, 3, 255]) });
console.log(JSON.stringify(r));
