---
id: 005
title: Restructure the secrets root of trust
date: 2026-08-18
status: complete
repos_touched: [GilmanLab/secrets, GilmanLab/root]
related_sessions: [002, 003, 004]
---

## Goal

Execute session 002's `SECRETS_RESTRUCTURE_PLAN.md`: make the private secrets
repository recoverable outside AWS, define the lab v2 hierarchy and scope
conventions, document the model, remove stale tailnet-policy artifacts, and add
a metadata-only CI guard.

## Outcome

The goal was met. All seven existing SOPS files now use scoped AWS KMS for
routine access and a YubiKey-backed PGP recipient for break-glass recovery in
one alternative-recipient key group. Both decryption paths reproduce every
pre-change plaintext hash, the discarded fleet proof passed through both paths,
and companion implementation and ADR changes were squash-merged with passing
default-branch workflows.

## Key Decisions

- Target the Curve25519 encryption subkey
  `51098F038D5D9F84FE342036858A466C85A0979C!` explicitly -> the planned primary
  fingerprint caused SOPS to select the Ed25519 authentication subkey and
  produce an undecryptable recovery packet.
- Keep KMS and PGP in one SOPS key group -> either recipient can recover the
  data key; separate groups would require both trust roots through Shamir
  secret sharing and would not survive AWS loss.
- Treat one encryption context scope as one access boundary -> future workflow
  roles can receive only the scope they consume, while an unconditioned grant
  remains a defect.
- Commit generated but durable recovery material to the encrypted store -> ZFS
  recovery keys, bootstrap client keys, and image-factory signing keys must
  survive the infrastructure that consumes them; ephemeral runtime secrets do
  not belong in git.
- Add only the `fleet` creation rule, not a placeholder or speculative IAM role
  -> the first real fleet secret or consumer workflow should create the durable
  artifact or role.

## Changes

- `GilmanLab/secrets/.sops.yaml` and seven `*.sops.yaml` files — added the exact
  YubiKey encryption-subkey recipient beside the unchanged KMS/context model and
  added the `fleet` creation rule.
- `GilmanLab/secrets/scripts/check_sops_metadata.py` and `moon.yml` — added CI
  validation for the KMS ARN, exact `Repo`/`Scope` context, and PGP recipient
  without decrypting secret values.
- `GilmanLab/secrets/README.md` and `CONTRIBUTING.md` — documented the hierarchy,
  routine and recovery paths, generated-durable exception, update procedure,
  and future per-scope IAM pattern.
- `GilmanLab/secrets/network/tailscale/policy.hujson` and
  `.github/workflows/tailscale-acl.yml` — removed stale copies after confirming
  the canonical networking workflow was live and green.
- `GilmanLab/root/docs/docs/decisions/0003-use-kms-with-pgp-recovery-for-secrets.md`
  — recorded the root-of-trust decision and confirmation criteria; linked it
  from the docs home and navigation.
- GitHub repository settings for `GilmanLab/secrets` — enabled squash-only
  merges and automatic branch deletion.

## Open Threads

- Session 002 can close T33 from the verification report in this session's
  `NOTES.md`.
- No fleet secret or consumer IAM role was created. Add them when the first real
  fleet workflow exists.
- The Tailscale admin-console edit lock was not independently confirmed here;
  session 003 recorded that operator step as pending.
- GitHub rulesets cannot enforce PR flow for this private repository without
  GitHub Pro; the rulesets API returns HTTP 403.
- The unrelated `session-054/incusos-bootstrap-client` worktree now conflicts
  with updated `GilmanLab/secrets` `master` and was left untouched.

## Lessons

- A PGP primary fingerprint does not guarantee correct encryption-subkey
  selection in SOPS. Verify the actual packet recipient and run recovery with
  AWS credentials absent.
- A stale GnuPG agent can preserve old behavior after a client upgrade; restart
  the GnuPG services before treating exact-subkey failures as key defects.

## References

- [GilmanLab/secrets PR #21](https://github.com/GilmanLab/secrets/pull/21) —
  merge `879b16b`, CI run `32206899575`
- [GilmanLab/root PR #12](https://github.com/GilmanLab/root/pull/12) — merge
  `6915ad5`, GitHub Pages run `32206926941`
- [ADR-0003](https://github.com/GilmanLab/root/blob/master/docs/docs/decisions/0003-use-kms-with-pgp-recovery-for-secrets.md)
- Session 002 plan: `.journal/002/SECRETS_RESTRUCTURE_PLAN.md`
