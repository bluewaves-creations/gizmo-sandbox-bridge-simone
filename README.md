# gizmo-sandbox-bridge

Cloudflare Sandbox Worker that lets [Gizmo NXT](https://github.com/bertranddour/gizmo-nxt) run skill scripts in your own Cloudflare account. Build-your-own-cloud, no shared infrastructure.

[![Deploy to Cloudflare](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/bluewaves-creations/gizmo-sandbox-bridge)

## What this is

When you import a skill into Gizmo NXT (e.g. `pdf-factory` from [Skills Boutique](https://github.com/bluewaves-creations/skillsboutique-skills)), the agent reads the skill's instructions and runs its Python scripts to produce outputs. Those scripts need a Linux environment with Python 3.13 and a stack of libraries (`xhtml2pdf`, `reportlab`, `pyhanko`, `matplotlib`, `ebooklib`, …) — well beyond what an iOS or macOS app can host on-device.

This worker is the bridge. It wraps Cloudflare's [Sandbox SDK](https://developers.cloudflare.com/sandbox/) — which gives every chat discussion its own isolated VM-backed Linux container — behind a stable HTTP API. Gizmo NXT calls that API with your AI Gateway token; the sandbox executes the skill script; the output flows back to the agent.

The whole thing runs in your Cloudflare account on your Workers Paid plan. No Bluewaves Boutique servers, no shared compute, no shared data path.

## Prerequisites

- A Cloudflare account on the **Workers Paid plan** ($5/month). Containers and Durable Objects, the primitives this worker uses, are paid-plan-only. The free plan can sign up; you'll need to upgrade once before deploying.
- Your existing **AI Gateway token** (`cf_api_token` in Gizmo Settings). The bridge reuses this same value as its `SANDBOX_API_KEY` — no new credential to manage.
- Tap-to-deploy works in any browser; you don't need `wrangler` or Docker locally.

## Deploy

[![Deploy to Cloudflare](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/bluewaves-creations/gizmo-sandbox-bridge)

The button takes you through Cloudflare's deploy wizard. It will:

1. Prompt for your Cloudflare login.
2. Confirm the Workers Paid plan (upgrade prompt if you're on Free).
3. Fork this repo into your account.
4. **Prompt for the `SANDBOX_API_KEY` secret** — paste your **AI Gateway token** (the `cf_api_token` value already in Gizmo Settings → Gateway → API Token). The bridge reuses this same token; one Keychain entry serves both surfaces.
5. Provision the Container, the `Sandbox` and `WarmPool` Durable Objects, and the cron trigger.
6. Build the Docker image (~3 minutes the first time — the skill stack pre-installs ~17 Python packages including `reportlab`, `xhtml2pdf`, `pyhanko`, `matplotlib`, `ebooklib`).
7. Print your bridge URL (`https://gizmo-sandbox-{xxx}.{your-subdomain}.workers.dev`).

Copy that URL into **Gizmo → Settings → Skill Sandbox → Bridge URL**, tap **Test connection**, and you're done. No CLI, no Mac required — works fully in mobile Safari from iPhone or iPad.

### Manage the secret later

If you ever need to rotate `SANDBOX_API_KEY`, or you skipped the wizard prompt and need to set the value manually, do this from the Cloudflare dashboard (no CLI required):

1. Open <https://dash.cloudflare.com> → log in.
2. **Workers & Pages** → click the `gizmo-sandbox` worker.
3. **Settings** tab → **Variables and Secrets** section → **Add**.
4. Type: **Secret** (encrypted, not Plaintext). Name: `SANDBOX_API_KEY`. Value: paste your AI Gateway token.
5. **Save and deploy** — the worker auto-redeploys (~5–10 s).

This dashboard path works on any browser including iOS/iPadOS Safari.

### Or deploy via wrangler CLI

If you prefer the terminal:

```bash
git clone https://github.com/bluewaves-creations/gizmo-sandbox-bridge.git
cd gizmo-sandbox-bridge
npm install
npx wrangler login
npx wrangler secret put SANDBOX_API_KEY  # paste your AI Gateway token
npx wrangler deploy
```

The `secrets.required` block in `wrangler.jsonc` makes `wrangler deploy` fail with a clear error if `SANDBOX_API_KEY` isn't configured — a second guardrail beyond the wizard prompt.

## How it's configured

`wrangler.jsonc` ships with sensible defaults for personal use:

| Setting | Default | Why |
|---|---|---|
| `instance_type` | `"basic"` | 1 GiB RAM / 4 GB disk per sandbox. `pdf-factory`'s xhtml2pdf+reportlab+lxml stack peaks ~400-600 MiB; `lite` (256 MiB) would OOM. Upgrade to `standard-1` (4 GiB / 8 GB) in the Cloudflare dashboard for heavy multi-user workloads. |
| `max_instances` | `5` | Five concurrent sandboxes per account. Each chat discussion that's actively executing scripts gets its own isolated VM. Bump in the dashboard if you have more than five concurrent users. |
| `WARM_POOL_TARGET` | `"0"` | No pre-warmed containers — first `/exec` after sandbox sleep adds ~2-3 s cold-start. Set to `1` if you want instant boots (but you're billed for memory + disk on the warm container). |
| `WARM_POOL_REFRESH_INTERVAL` | `"10000"` | 10 s. Only relevant if `WARM_POOL_TARGET > 0`. |
| `preview_urls` | `false` | We don't expose sandbox-served HTTP. Outputs come back through the bridge API. |

## Updating

When this repo bumps `@cloudflare/sandbox` (and the matching Docker base image), redeploy:

- **Via Deploy button**: tap it again. The wizard re-runs against `main` and rebuilds the image.
- **Via CLI**: `git pull && npm install && npx wrangler deploy`.

The pinned version lives in `package.json` (`@cloudflare/sandbox: 0.9.2`) AND in `Dockerfile` (`FROM cloudflare/sandbox:0.9.2`). Cloudflare's [version-sync rule](https://developers.cloudflare.com/sandbox/configuration/dockerfile/) requires both to match; we never bump one without the other.

### Updating from v0.9.2-bridge.1

If you deployed this bridge before tag `v0.9.2-bridge.2` and set `SANDBOX_API_KEY` manually via the dashboard or CLI, **no action is needed** when you redeploy. The wizard's secret prompt only fires for unconfigured secrets — your existing value is preserved. The `secrets.required` validation will pass on first deploy because the secret is already set.

Future Deploy-button users on this version will see the prompt natively; the manual dashboard step is no longer required for fresh deployments.

## Sharing one bridge across multiple users

A single deployed bridge can serve multiple Gizmo users on the same Cloudflare account natively — sandbox isolation is per `sandboxId`, and Gizmo derives a unique `sandboxId` from each chat discussion's UUID, so two humans in two discussions can never collide on shared state. Considerations:

- **Trust model**: every user with the bridge URL + token can run scripts on your Cloudflare account. They share your quota and Workers Logs.
- **Quota**: Workers Paid includes 25 GiB-hr memory + 375 vCPU-min + 200 GB-hr disk per month. A single user running `pdf-factory` ~30 min/day fits under the free quota. Multi-user budgets accordingly (active CPU billed only since [Nov 2025](https://developers.cloudflare.com/changelog/post/2025-11-21-new-cpu-pricing/), so cost scales with use).
- **Per-Apple-ID sync**: each Gizmo user pastes the URL + token into Settings on their first device. iCloud Keychain syncs the token across that user's devices, but does not cross Apple IDs. Manual share (Notes, password manager, secure DM) is the v1 onboarding path within a trust circle.

## Local health-check

After deployment:

```bash
bash script/health-check.sh https://gizmo-sandbox-bridge-{xxx}.{subdomain}.workers.dev <your-token>
```

Six curl tests verify auth + sandbox lifecycle + `/exec` SSE + file PUT/GET. Exit 0 on success, 1 on any failure.

## What runs inside the sandbox

The `Dockerfile` extends `cloudflare/sandbox:0.9.2` with three layers:

1. **Upstream tooling** (verbatim from `cloudflare/sandbox-sdk/bridge/worker`): `tar git curl wget ripgrep jq procps sed gawk`, Python 3.13 via [uv](https://docs.astral.sh/uv/), non-root `sandbox` user, workspace at `/workspace`.
2. **Gizmo skill stack**: `reportlab pypdf markdown lxml pillow html5lib cssselect2 pyhanko python-bidi arabic-reshaper matplotlib ebooklib beautifulsoup4 PyYAML` + `--no-deps rlpycairo svglib xhtml2pdf` (matches `pdf-factory/scripts/install_deps.py` rationale — avoids the pycairo C-extension build).
3. **App data**: nothing pre-loaded. Skill files (`SKILL.md`, `scripts/`, `assets/`) upload from the user's device on first `/exec` per discussion; outputs flow back to the agent and the container goes idle.

Need additional packages for a custom skill? Fork this repo, add a `RUN uv pip install …` layer to `Dockerfile`, redeploy.

## Pricing reality

For a single user running `pdf-factory` in a few discussions per day:

- Workers Paid: $5/month flat
- Sandbox usage: well under the 25 GiB-hr memory / 375 vCPU-min / 200 GB-hr disk monthly free quota
- Total: $5/month

For 10 active users sharing the bridge, expect to drift $5–15/month over the free quota depending on render frequency. Cloudflare Containers bills per active vCPU-second, so idle time is free.

## Architecture

```
┌─────────────────┐                ┌─────────────────────────────┐
│ Gizmo NXT (iOS  │   HTTPS +      │ gizmo-sandbox-bridge worker │
│ + macOS) Agent  │ ──Bearer──→    │ (Hono + @cloudflare/sandbox)│
│ tools call      │                │                             │
│ sandbox_exec /  │                │   ↓ getSandbox(env, "disc-X")│
│ read_file /     │                │                             │
│ write_file      │ ←──SSE/JSON──  │   Sandbox Durable Object    │
└─────────────────┘                │   ↓                         │
                                   │   Container ("basic", 1 GiB)│
                                   │   /workspace/skill/<name>/  │
                                   │   /workspace/input/         │
                                   │   /workspace/output/        │
                                   └─────────────────────────────┘
```

One sandbox per chat discussion. Sandboxes sleep after 10 minutes of inactivity (Cloudflare default). Skill files re-upload on wake — they're small (a few MB), so the cold-start cost is dominated by the container boot itself.

## Documentation

- [Cloudflare Sandbox SDK](https://developers.cloudflare.com/sandbox/)
- [Wrangler configuration reference](https://developers.cloudflare.com/sandbox/configuration/wrangler/)
- [Bridge HTTP API reference](https://developers.cloudflare.com/sandbox/bridge/http-api/)
- [Containers pricing](https://developers.cloudflare.com/containers/pricing/)
- [Gizmo NXT Skills system](https://github.com/bertranddour/gizmo-nxt/blob/main/docs/agent/agent.md#skill-system)
- [Agent Skills open standard](https://agentskills.io/)

## License

MIT — see [LICENSE](./LICENSE).
