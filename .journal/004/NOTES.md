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

## 2026-08-18 17:44 — AWS migration completed
Executed session 002's T35 migration plan end to end. No ordinary OpenTofu
apply was run. The new private `GilmanLab/aws` repository is the sole writer;
the legacy roots and stale publisher workflow are removed from default branches.

Final destination state and normal-plan verification:

| Root | Lineage | Serial | Instances | Normal plan |
| --- | --- | ---: | ---: | --- |
| `aws/lab-foundation` | `81c70c03-eca4-1bea-913a-875cbd7698fc` | 3 | 12 | 0/0/0 |
| `aws/github-oidc` | `11044351-63aa-e957-f879-2720ed3e0f66` | 1 | 1 | 0/0/0 |
| `network/tailscale` | `4a38802a-23fd-5350-d8e1-bb1077cecf87` | 6 | 8 | 0/0/0 |
| `security/pki/root-ca` | `41c7cf2f-3fce-cee1-dfd7-24bc9488c9cd` | 1 | 2 | 0/0/0 |
| `aws/subnet-router` | `3b1efd8a-aa89-90b3-1742-14745e5a6469` | 6 | 22 | 0/0/0 |
| `aws/keycloak` | `27d73489-f2c9-8e97-0ea4-712ddde3f07f` | 29 | 39 | 0/0/0 |

Identity audit after cutover:
- SOPS KMS key remains `arn:aws:kms:us-west-2:186067932323:key/2aba1d94-6eaf-4d80-8d26-2077f32fd7c5` (Enabled).
- Root-CA KMS key remains `arn:aws:kms:us-west-2:186067932323:key/5b585512-8604-43ce-b416-90fbd3cffcfa` (Enabled).
- Private `glab.lol` zone remains `Z009084217D5KKVQERJY3`; public
  `acme.glab.lol` remains `Z09426053F18LZ8FZXFFK`.
- Subnet router remains running as `i-07878bb4aa9896dd4`, role
  `glab-aws-subnet-router`, EIP `44.235.183.135`, and Tailscale address
  `100.80.89.100`.
- Keycloak remains running as `i-069f5e943c6e11092` at `172.16.0.115`, with
  `id.glab.lol` pointing there and data volume `vol-09baa3d716d956887` attached.
- Broker Lambda `glab-github-token-broker` remains Active. The shared GitHub
  OIDC provider imported cleanly into `aws/github-oidc`.

Merged changes:
- `GilmanLab/aws` PR #1 (`4cfb0fd`): six roots, all-root backendless CI, repo
  operator contract, squash-only settings, and Tailscale backend migration.
- `GilmanLab/infra` PR #57 (`fbebfe9`): removed all six legacy writers and
  Moon registrations; README points to the new repository.
- `GilmanLab/infra` PR #58 (`372a9d2`): retained ignore behavior for a
  pre-existing local Keycloak `tfplan` without deleting it.
- `GilmanLab/platform` PR #70 (`df6c3b0`): removed the workflow referencing the
  destroyed `glab-github-token-broker-publisher` role.
- `GilmanLab/root` PR #11 (`9fd7575`): `init.sh` now bootstraps private
  `GilmanLab/aws` beside `networking`.

State retirement and rollback evidence:
- Phase-0 backups/version inventories are mode-0600 files under mode-0700
  `/tmp/gilmanlab-aws-migration-20260819`; retain only for the rollback window,
  then remove the directory.
- Empty legacy `aws/github-token-broker.tfstate` retired with versioned delete
  marker `QzXOaJTBhh54jq93rKfGKCbZj3Yzc07y`; 11 prior versions remain recoverable.
- Old-account `s3://gilmanlab-tfstate/network/tailscale.tfstate` intentionally
  remains at version `eOGuI.I4OiV5yFZRYCln_Xkt_eNq4ZxT` for rollback. Delete it
  only after the rollback window; never touch the similarly named old root-CA
  object.

Plan deviations / corrections for session 002:
- Tombstone state also contained the two expected cached data-source instances;
  both were removed with the retained OIDC resource after exact-list validation.
- Session 002's Keycloak instance fact (`i-01b...`) was stale. The Phase-0
  captured state and live AWS both identify `i-069f5e943c6e11092`; this identity
  was preserved.
- Keycloak's refresh-only plan detected provider-computed EBS attachment and
  empty root-volume tag metadata. Its normal plan was 0/0/0, so the refresh-only
  plan was deliberately not applied.
- Initial Tailscale destination initialization created backend metadata before
  state push. Resource payloads were byte-equal after excluding lineage/serial;
  the source lineage was restored with a forced state push. The destination
  serial is 6 (source was 5) because the backend write increments serial.

Session 002 handoff: close T35, unblock T33, and open a separate task to destroy
Keycloak only after Zitadel serves. Session 004 did not mutate session 002's
active files under concurrent journal ownership; this entry is the handoff
report for that session to ingest.

## 2026-08-18 18:01 — Close
Session goal met. The AWS migration and cutover landed through
`GilmanLab/aws` PR #1, `GilmanLab/infra` PRs #57 and #58,
`GilmanLab/platform` PR #70, and `GilmanLab/root` PR #11. All four local
default checkouts are clean and fast-forwarded; session implementation
worktrees were removed.

Final handoff: `GilmanLab/aws` is the sole writer for all six migrated roots,
and every normal plan was 0/0/0 with critical identities preserved. Retain the
mode-0700 scratch backups and old-account Tailscale state only through the
rollback window, then remove both without touching the old root-CA state.
Session 002 should ingest the report above, close T35, unblock T33, and track
Keycloak teardown after Zitadel serves.
