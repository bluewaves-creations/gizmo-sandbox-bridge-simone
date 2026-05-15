/**
 * gizmo-sandbox-bridge — Cloudflare Sandbox Worker for Gizmo NXT
 *
 * Thin wrapper around the bridge from @cloudflare/sandbox/bridge.
 * All API routes, pool management, and authentication are handled by the
 * bridge factory; this module exists to wire the Durable Object exports
 * Wrangler needs and to keep the bridge version pinned alongside our
 * custom Dockerfile (see ./Dockerfile and package.json — they must match).
 *
 * To upgrade: bump the @cloudflare/sandbox pin in package.json AND the
 * `FROM cloudflare/sandbox:<tag>` line in Dockerfile in lock-step (per
 * Cloudflare's `developer.cloudflare.com/sandbox/configuration/dockerfile/`
 * version-sync rule).
 */

import { bridge } from '@cloudflare/sandbox/bridge';

// Re-export Sandbox so Wrangler can wire up the Durable Object binding.
export { Sandbox } from '@cloudflare/sandbox';

// Re-export WarmPool so Wrangler can wire up its Durable Object binding.
export { WarmPool } from '@cloudflare/sandbox/bridge';

export default bridge({
  async fetch(_request: Request, _env: Env, _ctx: ExecutionContext): Promise<Response> {
    return new Response('OK');
  },

  async scheduled(_controller: ScheduledController, _env: Env, _ctx: ExecutionContext): Promise<void> {
    // Application-specific scheduled logic (runs after pool priming).
  }
});
