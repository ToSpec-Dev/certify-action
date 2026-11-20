# AGENTS.md — repo conventions for `ToSpec-Dev/certify-action`

A **composite GitHub Action** that wraps the [`tospec` CLI](https://github.com/ToSpec-Dev/cli)
so a partner can certify their API integration against a [ToSpec](https://tospec.dev)
suite on every push. This repo is public, Apache-2.0, and a marketing surface —
**no platform-internal references, no tenant/test data, no secrets**; README quality
is a deliverable.

## The one rule that governs this repo

**This is packaging, not logic.** The Action downloads the `tospec` binary and runs it;
every decision (session lifecycle, pass/fail, remediation rendering) belongs to the CLI
and the platform behind it. If a change adds domain behavior, it belongs in the CLI or
the platform — not in `action.yml`. The Action's only jobs are: resolve the runner
OS/arch → binary, run `tospec run --wait`, surface `tospec remediation` on failure, and
map the CLI exit code to the step outcome.

## Conventions

- **Composite action, `shell: bash`.** No Docker container action (a container runtime
  is heavier than downloading one static binary) and no JavaScript action (no
  `node_modules` to maintain). One `action.yml`, one bash step.
- **The binary is downloaded, not built.** It comes from a pinned `ToSpec-Dev/cli` release
  (self-contained single file — the runner needs no .NET). Support `cli-version: latest`
  and an explicit tag.
- **The exit-code contract is the CLI's** (`0` pass / `1` fail / `2` error). The Action
  maps it to the step via `fail-on` (default: fail on `1` or `2`).
- Inputs pass through as `TOSPEC_URL` / `TOSPEC_PAT` env and CLI flags; never log the PAT.
- Keep `action.yml`'s bash `set -euo pipefail` and quote everything — a partner's CI
  depends on it being robust.

## Versioning

Tag releases `vN.M.K` and maintain a moving major tag (`v1`) so `uses:
ToSpec-Dev/certify-action@v1` keeps working. Pin the default `cli-version` to a released CLI
tag when cutting a major, so `@v1` is reproducible.

## Testing

There is no unit surface here — the Action is validated two ways:
1. `ci.yml` checks `action.yml` parses.
2. The real proof is the **dogfood**: `ToSpec-Dev/sample-partner`'s workflow uses this Action
   against a seeded suite and must stay green. That is the end-to-end test for this repo.
