// Run the official pandoc.wasm (WASI) under Node's WASI, to show the pptx writer runs with no native binary.
// usage: node wasm-pandoc.mjs <workdir> <pandoc args...>   (paths in args are relative to /work)
import { readFile } from "node:fs/promises";
import { WASI } from "node:wasi";
const [workdir, ...args] = process.argv.slice(2);
const wasi = new WASI({ version: "preview1", args: ["pandoc", ...args], env: {}, preopens: { "/work": workdir }, returnOnExit: true });
const mod = await WebAssembly.compile(await readFile(new URL("../dl/wasm/x/pandoc-3.13-wasm/pandoc.wasm", import.meta.url)));
const inst = await WebAssembly.instantiate(mod, wasi.getImportObject());
const t = Date.now();
const code = wasi.start(inst);
console.error(`exit ${code} in ${Date.now() - t} ms`);
