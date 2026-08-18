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

## 2026-08-18 17:50 — GitOps pipeline live; subject claim corrected
Correction to the 17:35 entry: the trust credential subject recorded there,
`repo:GilmanLab/networking:*`, is wrong. The first `Validate policy` run failed
with `token exchange failed with status 403`. A throwaway workflow on branch
`chore/oidc-debug` (since deleted) minted a token with the same audience and
printed its claims:
  iss https://token.actions.githubusercontent.com
  aud api.tailscale.com/THZctfF8wr11CNTRL-ka6ybAnLf721CNTRL
  sub repo:GilmanLab@66194346/networking@1334494603:ref:refs/heads/chore/oidc-debug
The GilmanLab organization issues OIDC subjects in GitHub's immutable form with
numeric org and repo IDs, so a name-based subject pattern can never match. The
correct value is `repo:GilmanLab@66194346/networking@1334494603:*`; the user
updated the credential and the rerun passed.
Rollout completed:
- `GilmanLab/networking` PR #6 squash merged as `b160c71`. `Validate policy`
  passed (control `266e13bf`, local `73f11bf0`); `Apply policy` on master wrote
  the policy; a second dispatch run reported control == local == `73f11bf0` and
  `no update needed, doing nothing`, proving convergence.
- `GilmanLab/root` PR #9 squash merged as `3ef719a` (ADR-0002, policy reference,
  change runbook, index and nav).
- `GilmanLab/root` PR #10 squash merged as `7f2f569`: corrected the documented
  subject and added a 403 escalation path to the runbook.
- Implementation worktrees and branches removed in both repos; `git ls-files
  .journal` is empty on the root default branch.
Learned: `gh workflow run` requires the workflow to exist on the default branch,
so an ad-hoc debug workflow on a side branch needs a `push` trigger instead of
`workflow_dispatch`. Also, a stale chrome-devtools MCP Chrome can hold its
profile lock for days and must be killed before a new instance starts.
Remaining: the user enables Tailscale's `Prevent edits in the admin console`
with the external reference to `tailscale/policy.hujson`. Deferred by choice: ACL
`tests`, a cron re-apply, branch protection, and any `grants` migration.
Next: session close, promoting the credential, variable, and drift facts into
TECH_NOTES.

## 2026-08-18 16:48 — Close
Correction: the entries labeled `17:35` and `17:50` were written between roughly
16:20 and 16:47 local time. Their timestamps are wrong; this entry uses the
verified clock.
Merged and landed: `GilmanLab/networking` PR #6 (`b160c71`), `GilmanLab/root`
PR #9 (`3ef719a`), `GilmanLab/root` PR #10 (`c1ed11b`). Local `master` in both
`/Users/josh/code/lab2` and `/Users/josh/code/lab2/networking` fast-forwarded to
those tips; implementation worktrees and branches removed; `git ls-files
.journal` empty in both.
Recorded: `SUMMARY.md` written, `INDEX.md` row 003 set to complete, and
`TECH_NOTES.md` gained a Tailscale policy section (policy path, workflow, tailnet
ID, repository variables, trust credential scopes, the immutable OIDC subject
form, inert drift detection) plus a correction that the MkDocs site now lives
only in the meta repository.
Hand-off: the tailnet policy pipeline is live and converged. The developer still
has to enable `Prevent edits in the admin console` with the external reference to
`tailscale/policy.hujson`. Nothing else is in flight.
