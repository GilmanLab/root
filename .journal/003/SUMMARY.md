---
id: 003
title: Manage the Tailscale policy with GitOps
date: 2026-08-18
status: complete
repos_touched: [GilmanLab/root, GilmanLab/networking]
related_sessions: [001]
---

## Goal

Put the personal tailnet's policy file (tailnet ID `THZctfF8wr11CNTRL`) under
version control in the `networking` repository and keep Tailscale in sync with it
through Tailscale's GitHub Action.

## Outcome

The goal was met. `GilmanLab/networking` now owns `tailscale/policy.hujson`, and
`.github/workflows/tailscale-acl.yml` validates it on pull requests and applies it
to the tailnet on merge to `master`. Convergence was proven: after the first
apply, a second run reported identical control and local checksums with
`no update needed, doing nothing`. The central documentation set gained ADR-0002,
a policy reference, and a change runbook.

The developer performed the Tailscale console work and set the repository
variables. One step remains with them: enabling **Prevent edits in the admin
console** with an external reference to the policy file.

## Key Decisions

- Keep the policy in `GilmanLab/networking` rather than a dedicated private
  repository -> it belongs beside the network implementation, and this policy
  contains no user email addresses, so the public repository is acceptable.
- Authenticate CI with a workload identity federation credential instead of an
  OAuth secret or API key -> no long-lived credential is stored, and API tokens
  expire on their own.
- Use one trust credential rather than separate read and write credentials -> a
  read/write split protects against nothing the single owner cannot already do.
- Do not add `tests`/`sshTests` to the policy -> `gitops-pusher test` already
  validates the whole policy through `/acl/validate` with no tests present, so
  tests would only restate six flat rules and force a two-file edit per
  intentional change. Revisit if the policy outgrows one screen.
- Rely on the admin-console lock for drift rather than checksum alerting ->
  `gitops-pusher` detects console edits through a cache file that ephemeral CI
  never persists, so its drift warning cannot fire in this setup.
- Remove `tag:dntls` -> the developer confirmed it is unused.
- Import the policy verbatim first, then document -> proves the pipeline before
  conflating it with policy changes.

## Changes

- `GilmanLab/networking/tailscale/policy.hujson` — the tailnet policy, with every
  `tag:dntls` element removed (tag owner, both ACL rules, and the admin SSH rule)
  and comments recording each section's intent.
- `GilmanLab/networking/.github/workflows/tailscale-acl.yml` — `test` on pull
  requests, `apply` on push to `master` and manual dispatch, using
  `tailscale/gitops-acl-action` pinned to `5a4a17f` (tag `v1` = `v1.5.2`);
  `permissions: {}` at the top with `contents: read` and `id-token: write` on the
  job; concurrency group `tailscale-acl` without cancellation.
- `GilmanLab/networking/.gitignore` — ignores `version-cache.json`.
- `GilmanLab/root/docs/docs/decisions/0002-manage-tailscale-policy-with-gitops.md`
  — records the decision, alternatives, and observable confirmation checks.
- `GilmanLab/root/docs/docs/reference/networking/tailscale-policy.md` — tailnet
  identity, canonical file locations, tag catalog, auto-approved routes,
  credential and variable inventory, and why drift detection is inert.
- `GilmanLab/root/docs/docs/runbooks/tailscale-policy-change.md` — change,
  verification, revert, emergency-edit, and escalation procedures.
- `GilmanLab/root/docs/docs/index.md`, `GilmanLab/root/docs/mkdocs.yml` —
  navigation for the new pages plus a new Runbooks section.

## Open Threads

- The developer still needs to enable **Prevent edits in the admin console** and
  set the external reference to `tailscale/policy.hujson`.
- The auto-approved ranges `10.10.0.0/16`, `172.16.0.0/16`, `192.168.1.0/24`, and
  `192.168.2.0/24` are authoritative for the tailnet today and must be reconciled
  with the Lab v2 address plan when that plan exists.
- Deferred by choice: ACL `tests`, a scheduled re-apply for self-healing
  convergence, branch protection requiring the ACL check, and any migration from
  `acls` to `grants`.
- `GilmanLab/networking` still has an untracked `docs/` directory left over from
  the documentation move in session 002. It predates this session and was left
  alone.

## Lessons

- Do not assume the plain GitHub OIDC subject format. This organization issues
  immutable subjects with numeric IDs
  (`repo:GilmanLab@66194346/networking@1334494603:...`), so a name-based subject
  pattern fails the Tailscale token exchange with HTTP 403 before scopes are
  evaluated. Print the actual claims rather than guessing.
- `gh workflow run` only finds workflows that exist on the default branch, so an
  ad-hoc debug workflow on a side branch needs a `push` trigger.
- A stale `chrome-devtools-mcp` Chrome can hold its profile lock for days and
  must be terminated before a new instance starts; the profile's cookies survive.
- Validation coverage can be free: check what a CI tool already does before
  adding assertions that duplicate the configuration under test.

## References

- [GilmanLab/networking PR #6](https://github.com/GilmanLab/networking/pull/6) — commit `b160c71`
- [GilmanLab/root PR #9](https://github.com/GilmanLab/root/pull/9) — commit `3ef719a`
- [GilmanLab/root PR #10](https://github.com/GilmanLab/root/pull/10) — commit `c1ed11b`
- [GitOps for Tailscale with GitHub Actions](https://tailscale.com/docs/integrations/github/gitops)
- [Tailscale workload identity federation](https://tailscale.com/docs/features/workload-identity-federation)
- Prior session: `.journal/001/SUMMARY.md`
