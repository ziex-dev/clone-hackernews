import { worker } from "ziex/cloudflare";
// @ts-ignore
import module from "../zig-out/bin/hackernews.wasm";


export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext) {
    return worker.run({
      request,
      env,
      ctx,
      module,
      kv: { default: env.ZX_HN }
    });
  },
} satisfies ExportedHandler<Env>;