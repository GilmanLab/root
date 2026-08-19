---
id: 004
title: Migrate AWS infrastructure into GilmanLab/aws
date: 2026-08-18
status: complete
repos_touched: [GilmanLab/aws, GilmanLab/infra, GilmanLab/platform, GilmanLab/root]
related_sessions: [002]
---

## Goal

Execute session 002's T35 migration plan: move all six AWS/OpenTofu roots from
the deprecated `GilmanLab/infra` repository into a new private `GilmanLab/aws`
repository without changing state keys or live resource identities. Every
migrated root had to produce a normal plan with zero creates, changes, and
destroys.

## Outcome

The goal was met. `GilmanLab/aws` is now the sole writer for the six roots, all
six destination plans were 0/0/0, CI passed, the legacy roots and obsolete token
broker publisher were removed, and the root meta repository now bootstraps the
new private repository. No ordinary OpenTofu apply ran during the migration.

Live identity checks passed after cutover: both KMS keys, both hosted zones, the
subnet-router instance/role/EIP/Tailscale address, the Keycloak instance/data
volume/DNS record, the broker Lambda, and the shared GitHub OIDC provider were
preserved.

## Key Decisions

- Import the retained GitHub OIDC provider into a minimal new root, then remove
  the exact three tombstone state instances -> this avoided ever applying the
  obsolete broker root and risking resource resurrection.
- Move Tailscale state by pull/push across accounts -> no single principal
  spanned both backends; source lineage was restored after verifying the
  resource payloads were identical apart from backend metadata.
- Treat normal plans, not refresh-only metadata, as the migration acceptance
  gate -> Keycloak's refresh-only plan reported provider-computed EBS metadata,
  while the actionable plan was clean, so no state-only refresh was applied.
- Preserve the old-account Tailscale object for a rollback window -> the live
  writer moved, but immediate deletion would have reduced recoverability.
- Remove legacy source roots only after all destination plans and CI passed ->
  this minimized the dual-writer interval while preserving rollback evidence.

## Changes

- `GilmanLab/aws` — created the private repository with roots
  `aws/lab-foundation`, `aws/github-oidc`, `network/tailscale`,
  `security/pki/root-ca`, `aws/subnet-router`, and `aws/keycloak`; added
  backendless CI, operator guidance, and squash-only repository settings.
- `GilmanLab/infra` — removed the six legacy writers and Moon registrations,
  pointed operators to `GilmanLab/aws`, and retained ignores for local OpenTofu
  plans and provider caches.
- `GilmanLab/platform/.github/workflows/publish-github-token-broker.yml` —
  removed the workflow that referenced the destroyed publisher role.
- `GilmanLab/root/init.sh`, `.gitignore`, and `AGENTS.md` — made
  `GilmanLab/aws` a first-class independent checkout beside `networking`.
- AWS state — created `aws/github-oidc.tfstate`, migrated
  `network/tailscale.tfstate` into the lab bucket, and retired the empty legacy
  `aws/github-token-broker.tfstate` with a versioned delete marker.

## Open Threads

- After the rollback window, remove
  `/tmp/gilmanlab-aws-migration-20260819` and explicitly delete the old-account
  `s3://gilmanlab-tfstate/network/tailscale.tfstate`; never touch the similarly
  named old root-CA object.
- Session 002 should close T35, unblock T33, and track a separate Keycloak
  teardown only after Zitadel serves.
- Keycloak's refresh-only plan still observes provider-computed EBS attachment
  and empty root-volume tag metadata; its normal plan is clean.

## Lessons

- A freshly initialized destination backend can assign unrelated lineage even
  when a state push populates the correct resources. Compare normalized state,
  then deliberately preserve source lineage rather than accepting metadata
  drift implicitly.
- Cached data-source instances can remain in a tombstone state. Exact-list
  validation distinguished harmless cache entries from unexpected managed
  infrastructure.
- Session 002's recorded Keycloak instance ID was stale. Phase-0 state and live
  AWS both identified `i-069f5e943c6e11092`; migration evidence must outrank a
  planning document's cached identity.

## References

- [GilmanLab/aws PR #1](https://github.com/GilmanLab/aws/pull/1) — `4cfb0fd`
- [GilmanLab/infra PR #57](https://github.com/GilmanLab/infra/pull/57) — `fbebfe9`
- [GilmanLab/infra PR #58](https://github.com/GilmanLab/infra/pull/58) — `372a9d2`
- [GilmanLab/platform PR #70](https://github.com/GilmanLab/platform/pull/70) — `df6c3b0`
- [GilmanLab/root PR #11](https://github.com/GilmanLab/root/pull/11) — `9fd7575`
- Session 002 plan: `.journal/002/AWS_MIGRATION_PLAN.md`
