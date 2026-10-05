import { Ziex } from "../zig-out/bindings/platforms/cloudflare";
import module from "../zig-out/bin/hackernews.wasm";

export default new Ziex<Env>({ module, kv: 'KV', db: 'DB' });