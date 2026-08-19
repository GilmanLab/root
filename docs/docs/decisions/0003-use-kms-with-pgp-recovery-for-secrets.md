---
status: accepted
date: 2026-08-18
---

# ADR-0003: Use AWS KMS with PGP Recovery for Secrets

## Context and Problem Statement

`GilmanLab/secrets` must remain usable during routine operation without
long-lived credentials and must also recover the lab if its AWS account or SOPS
KMS key is lost. The previous glab-era rule allowed only KMS recipients, making
the AWS account a single recovery dependency. What should protect SOPS data
keys for lab v2?

## Decision Drivers

- Use short-lived, scope-limited AWS credentials for normal operation.
- Preserve a physically controlled recovery path outside AWS.
- Keep access boundaries enforceable for automation principals.
- Retain recovery-critical generated secrets across a complete lab rebuild.
- Avoid changing existing encrypted-file paths or plaintext values.

## Considered Options

- Wrap every SOPS data key to AWS KMS and a YubiKey-backed PGP recipient in one
  key group.
- Continue using AWS KMS as the only recipient.
- Put KMS and PGP in separate SOPS key groups.
- Move secret storage immediately to Vault.

## Decision Outcome

Every SOPS file uses one key group containing two alternative recipients:

- the lab SOPS KMS key, with encryption context
  `Repo=GilmanLab/secrets` and a scope-specific `Scope` value; and
- Josh's YubiKey-backed PGP identity as a break-glass recipient.

SOPS targets the identity's Curve25519 encryption subkey explicitly. Selecting
the primary fingerprint allowed SOPS' OpenPGP implementation to choose the
Ed25519 authentication subkey, producing a packet the YubiKey could not
decrypt. The primary key remains the recovery identity; the configured
recipient is its encryption-capable subkey with exact-subkey selection.

Recipients inside one SOPS key group are alternatives: either KMS or the
YubiKey can recover the data key. Separate groups invoke Shamir secret sharing
and would require both trust roots, which does not survive AWS loss.

Routine automation uses KMS. PGP deliberately bypasses IAM scope boundaries;
its boundary is physical YubiKey custody. IAM roles live in `GilmanLab/aws` and
are created only for real consumers. Each role is restricted to one workflow,
the SOPS KMS key, and both encryption-context conditions:

- `kms:EncryptionContext:Repo = GilmanLab/secrets`
- `kms:EncryptionContext:Scope = <scope>`

An unconditioned KMS grant spans every scope and is a defect.

Non-generated secrets must live in `GilmanLab/secrets`. Generated but durable,
lab-recovery-critical secrets also live there as an exception, including
IncusOS ZFS recovery keys, the seed/bootstrap client private key, and the image
factory's cache-signing key. Ephemeral runtime-generated secrets are not
committed.

### Consequences

- Good, because ordinary access uses MFA-backed SSO or short-lived OIDC
  credentials and can be limited to one scope.
- Good, because physical PGP recovery remains available after total AWS loss.
- Good, because recovery-critical generated material survives the systems that
  normally consume it.
- Bad, because one physical recovery identity can bypass all IAM scope
  boundaries.
- Bad, because YubiKey custody and periodic PGP-only recovery tests become
  operational requirements.
- Bad, because recipient changes require rewrapping every affected SOPS data
  key and verifying both paths.

### Confirmation

The implementation conforms when:

- `.sops.yaml` in `GilmanLab/secrets` defines KMS and PGP in one key group for
  every scope;
- every encrypted file carries the expected KMS ARN, `Repo` and `Scope`
  context, and exact PGP encryption-subkey recipient;
- CI validates that metadata without AWS credentials or plaintext access;
- KMS-only decryption preserves the known plaintext hash for each file;
- a YubiKey decrypts at least one file per scope with AWS credentials absent;
- every consumer IAM policy conditions `kms:Decrypt` on both context values.

## Pros and Cons of the Options

### KMS and PGP in One Key Group

- Good, because either trust root can recover a data key independently.
- Good, because KMS remains compatible with per-scope least privilege.
- Bad, because compromise of either trust root can decrypt affected files.

### KMS Only

- Good, because all access is centrally auditable and conditionable in IAM.
- Bad, because loss of the AWS account or KMS key destroys the only decryption
  path.

### Separate KMS and PGP Key Groups

- Good, because decryption requires independent trust roots.
- Bad, because AWS loss prevents recovery, contradicting the primary goal.

### Vault Now

- Good, because Vault can issue dynamic credentials and centralize policy.
- Bad, because Vault depends on lab infrastructure and cannot be the root of
  trust for secrets needed to build that infrastructure.

## More Information

The canonical recipient, path rules, encryption context, and operational
commands are in the
[`GilmanLab/secrets` README](https://github.com/GilmanLab/secrets/blob/master/README.md).
The KMS key is managed by the `aws/lab-foundation` root in `GilmanLab/aws`;
consumer IAM roles will be implemented there when their workflows exist.
