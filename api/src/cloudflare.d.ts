// Tells workers-types about this Worker so `env` and `exports` from `cloudflare:*` are typed.
declare namespace Cloudflare {
  interface Env extends import("./env").Bindings {}
  interface GlobalProps {
    mainModule: typeof import("./index");
  }
}
