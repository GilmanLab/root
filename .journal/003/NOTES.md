---
id: 003
title: New session (goal pending)
started: 2026-08-18
---

## 2026-08-18 15:52 — Kickoff
Goal for the session: not yet stated. The user asked to start a new session; the
first substantive request will define the goal.
Current state of the world: `GilmanLab/root` is a meta repository that clones
`GilmanLab/networking` as an ignored independent repository. Session 001 is
closed and delivered the networking repository, its MkDocs toolchain and Pages
deployment, decision 0001 (VyOS owns Layer 3, switches own Layer 2), the
core-network design draft, and the authoritative hardware and physical-connection
references. Session 002 remains in-progress and is untouched by this session.
Open threads from 001: address/VLAN plan, DHCP/DNS/time ownership, config
rendering and deployment tooling, redundancy decision, architecture and runbooks
after implementation, and `docs.gilman.io` DNS verification.
Plan: wait for the user's actual request, then scope work, load task-relevant
skills, and create implementation branches inside the owning repository.

## 2026-08-18 16:05 — Tailscale search in ~/code/lab
Request: locate the Tailscale configuration in `~/code/lab` for migration into
the new lab repos.
Finding: there is no Tailscale implementation in `~/code/lab`. A
case-insensitive search across the whole tree, including gitignored files, and a
full-history filename search (`git log --all --name-only`) returned only:
- `docs/architecture/09_design_decisions/003_vyos_gitops.md` — ADR proposing
  GitHub Actions + Ansible + Tailscale (`tailscale/github-action@v2`,
  `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_SECRET`, `tags: tag:ci`) for VyOS deploys.
- `docs/architecture/09_design_decisions/007_image_pipeline_s3_intermediary.md`
  — Tailscale rejected as the image-transfer path.
- `docs/architecture/11_risks.md`, `docs/architecture/index.md`,
  `docs/architecture/appendices/A_repository_structure.md` — references to
  ADR 003.
- `infra/network/vyos/ansible/inventory/hosts.yml:9` — comment "Connect via
  Tailscale in CI/CD"; host actually comes from `$VYOS_HOST`, default
  `10.0.0.2`.
No `.github/workflows` in `~/code/lab` uses the Tailscale action; no ACL policy
file, no Ansible role, no VyOS `service tailscale` stanza.
Adjacent finding: the only real Tailscale artifacts on this machine are in
`~/code/infra` — `nixos/hosts/tailscale-router/` (NixOS host skeleton whose
configuration.nix ends with "Tailscale configuration will be added in a future
iteration", so no `services.tailscale`) and `secrets/services/tailscale.enc.yaml`
(SOPS/age-encrypted OAuth `client_id`, `client_secret`, and a `tags` list; last
modified 2025-11-16). `~/code/lab_old` and `~/code/homelab` contain no Tailscale
references at all.
Next: confirm with the user what "the Tailscale configuration" means, since
there is nothing executable to port from `~/code/lab`.

## 2026-08-18 16:40 — Tailscale GitOps plan proposed
Request: manage the personal tailnet policy (id `THZctfF8wr11CNTRL`) GitOps
style under `networking`, synced by Tailscale's GitHub Action.
Grounding gathered:
- `tailscale/gitops-acl-action@v1` is a composite action that installs Go and
  runs `go run tailscale.com/cmd/gitops-pusher@b4d39e2` with
  `--policy-file=<path>` and subcommand `test` or `apply`. Inputs: `tailnet`,
  `policy-file`, and one of `api-key`, `oauth-client-id`+`oauth-secret`, or
  `oauth-client-id`+`audience` (OIDC federated identity, needs
  `id-token: write`).
- gitops-pusher compares sha256 of `hujson.Format(local)` against the control
  ACL etag. Manual-edit detection uses `--cache-file` (default
  `./version-cache.json`); in ephemeral CI the cache is absent, so
  `cache.PrevETag` is seeded from control and drift detection is a no-op. The
  admin-console lock ("Prevent edits in the admin console") is the real control.
- Policy tests (`tests`, `sshTests`) require concrete `src`/`dst` entities; no
  wildcards. `autogroup:*` cannot be a test `src`, so admin-path tests need a
  user email.
- `GilmanLab/networking` is public with default branch `master` and currently
  tracks only `.gitignore`, `mise.toml`, `mise.lock`. Tailscale docs recommend a
  private repo because policy files often contain user emails; the owner email
  is already public in commit history.
- Existing SOPS-encrypted Tailscale OAuth client in `~/code/infra` is for node
  registration (auth_keys/tags), not `policy_file` scope. Do not reuse it.
Plan proposed: phase 1 verbatim policy import plus test/apply workflow in
`GilmanLab/networking` (`tailscale/policy.hujson`,
`.github/workflows/tailscale-acl.yml`, WIF credentials); phase 2 encode
invariants as `tests`/`sshTests` and prove the gate fails; phase 3 companion docs
in root (ADR 0002, `reference/networking/tailscale-policy.md`, runbook, nav,
`moon run docs:build`); phase 4 optional cron re-apply and branch protection.
Open questions for the user: purpose/naming of `tag:dntls`, the tailnet admin
login to use as a test `src`, whether the autoApprover CIDRs are authoritative
for the coming address plan, and whether to enable the admin-console lock now.
Next: user decision on the plan before any implementation branch is created.

## 2026-08-18 17:35 — Policy tests dropped; branches pushed
Correction to the 16:40 plan: the `tests`/`sshTests` phase was dropped. The user
objected that a single-owner tailnet makes deliberate changes the norm, and the
claimed benefit was already free: `gitops-pusher test` POSTs the whole policy to
`/api/v2/tailnet/<tailnet>/acl/validate` and fails on returned errors or
warnings with no `tests` block present. Tests would have duplicated the rules and
forced a two-file edit per change. Also dropped the two-credential read/write
split in favor of one credential, for the same single-owner reason.
User answers: remove `tag:dntls`; the four autoApprover CIDRs are authoritative
for now; lock the admin console (after the first successful apply). Browser-driven
console setup was abandoned mid-attempt at the user's request, so the console
work and the GitHub variables are the user's manual steps.
Delivered:
- `GilmanLab/networking` branch `feat/tailscale-policy-gitops`, commit `e4310f5`,
  pushed, PR intentionally not opened (a PR triggers `test`, which fails without
  the repo variables): `tailscale/policy.hujson` (policy minus every `tag:dntls`
  element), `.github/workflows/tailscale-acl.yml` (test on PR, apply on push to
  master plus dispatch, action pinned `5a4a17f` = tag `v1` = `v1.5.2`),
  `.gitignore` entry for `version-cache.json`.
- `GilmanLab/root` PR #9 from `docs/tailscale-policy-gitops`, commit `969ac3b`:
  ADR-0002, `reference/networking/tailscale-policy.md`,
  `runbooks/tailscale-policy-change.md`, index and nav. Build documentation check
  passed.
Verification performed: policy parsed with `github.com/tailscale/hujson` and
`Standardize` produced exactly the intended JSON; `actionlint` clean on the
workflow; strict MkDocs build passed and all three pages rendered.
Durable context for TECH_NOTES at close: workflow variables are
`TS_TAILNET`, `TS_POLICY_CLIENT_ID`, `TS_POLICY_AUDIENCE`; trust credential
subject `repo:GilmanLab/networking:*` with scopes `policy_file`,
`devices:posture_attributes`, `devices:core:read`; gitops-pusher drift detection
is inert in ephemeral CI because the `--cache-file` etag cache is never
persisted, so the console lock is the real control; both repos default to
`master`.
Next: user completes console setup and sets the three variables, then open the
networking PR, verify `Validate policy`, squash merge, confirm `Apply policy`,
merge root PR #9, and enable the console lock.
