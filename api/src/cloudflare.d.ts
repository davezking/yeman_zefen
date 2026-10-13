// Tells workers-types about this Worker so `env` and `exports` from `cloudflare:*` are typed.
import type { Bindings } from "./env";

declare global {
  namespace Cloudflare {
    interface Env extends Bindings {}
    interface GlobalProps {
      mainModule: typeof import("./index");
    }
  }
}
