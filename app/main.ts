import { Ziex } from "ziex";
import module from "../zig-out/bin/hackernews.wasm";

export default new Ziex<Env>({ module, kv: 'KV' });