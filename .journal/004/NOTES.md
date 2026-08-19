---
id: 004
title: New session (goal pending)
started: 2026-08-18
---

## 2026-08-18 17:19 — Kickoff
Goal for the session: not yet stated. The user asked only to create a new
session; the actual request follows.

Current state of the world:
- `GilmanLab/root` (`~/code/lab2`) is on `master` at `c1ed11b`, clean.
- Journal worktree `journal/jmgilman` at `.wt/journal-jmgilman`, clean, in sync
  with `origin`.
- Sessions 001 and 003 are complete; 002 remains `in-progress` and is owned by a
  different task (not touched here).
- Lab v2 networking: authoritative hardware, physical cabling, and L2/L3
  ownership documented (session 001). Tailscale policy is GitOps-managed in
  `GilmanLab/networking/tailscale/policy.hujson` with CI apply on merge
  (session 003).
- Known open threads: address plan / VLAN allocation / interface mapping still
  undefined; DHCP, DNS, and time-service ownership unassigned; VyOS and switch
  config rendering, deployment, and drift detection unselected; `docs.gilman.io`
  DNS unverified; Tailscale admin-console edit lock still needs enabling by the
  developer; untracked leftover `docs/` directory in the networking checkout.

Plan: wait for the user's request, then create a child-local Worktrunk
implementation worktree from the fetched default branch in whichever repository
the work targets, and integrate via a squash-merged GitHub PR.

## 2026-08-19 00:20 — AWS migration assigned
Goal for the session: execute session 002's `.journal/002/AWS_MIGRATION_PLAN.md`
today: move the six AWS/OpenTofu roots from deprecated `GilmanLab/infra` into
new private `GilmanLab/aws` while preserving state and live resource identities.

Acceptance and safety boundaries:
- Every migrated live root must plan `0 creates, 0 changes, 0 destroys` from the
  destination repo.
- Never ordinary-apply the legacy GitHub token broker tombstone root.
- Preserve both KMS key identities, IAM names, hosted zones, subnet-router
  identity, Keycloak instance/data volume, and all state keys.
- Freeze and capture state/version metadata before mutation; stop on unexpected
  tombstone resources, drift, identity mismatch, or authentication failure.
- Cut over the old repo only after destination verification, then report results
  and deviations back to session 002.

Plan: authenticate and capture read-only baselines; inspect org/repo conventions;
bootstrap `GilmanLab/aws`; carve the retained GitHub OIDC provider out of the
tombstone; migrate and verify roots in dependency order; remove old writers;
wire the new repo into lab2; validate CI/docs; checkpoint evidence.
