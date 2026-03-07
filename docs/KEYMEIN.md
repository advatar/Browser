# KeyMeIn Research Note

Date: 2026-03-07

## Current status in dBrowser

- `KeyMeIn` is present in this repo as a git submodule.
- `dBrowser` does not currently use `KeyMeIn` in its build or runtime path.
- It is not included in the Rust workspace or the JavaScript workspaces.
- No direct `@keymein/sdk` or `keymein-sdk` dependency is wired into the app manifests.

## Existing overlapping functionality

`dBrowser` already has local implementations for the main areas that `KeyMeIn` would touch:

- Capability quotas and revocation for agent actions
- GUI approval prompts for sensitive capabilities
- Per-user and per-agent wallet profiles with spend policy
- Agent wallet signing and broadcast flow
- An in-process gateway flow that mints local JWKS-backed decision JWTs and merchant/cart approvals

The current gateway path is local and demo-oriented rather than a real external attestation or identity service.

## Recommendation

Do not treat `KeyMeIn` as an active dependency today.

Adopt it only if the project needs production-grade attestation-gated signing, such as:

- Real identity or KAT-gated authorization instead of the current local gateway flow
- Threshold or policy-gated signing across chains
- Receipt and JWKS verification flows
- Browser wallet adapters that must integrate with an external signing policy system

If adopted, the first integration point should be the current gateway and wallet-signing boundary, not the browser core. Prefer a narrow adapter or SDK-based integration over pulling the whole `KeyMeIn` tree into the main workspace.
