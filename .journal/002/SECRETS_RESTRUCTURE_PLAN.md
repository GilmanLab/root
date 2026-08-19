# Secrets Restructure Plan — `GilmanLab/secrets` for Lab v2 (T33)

Status: ready for implementation. Drafted 2026-08-18 in session 002. The
implementing session reports back so session 002 closes T33 on its report.

Self-contained; no conversation history required. Companion context:
`.journal/002/VISION.md` (Secrets section) and the completed AWS migration
(`.journal/002/AWS_MIGRATION_PLAN.md`, executed by session 004 — the KMS key
and OIDC provider now live under `GilmanLab/aws`).

## Goal

Restructure the existing `GilmanLab/secrets` repo as lab v2's secret store:

1. Add the YubiKey-backed **PGP recovery recipient** to every SOPS key group
   (deliberate reversal of the glab-era KMS-only rule; rationale: the lab must
   be rebuildable if the AWS account is lost).
2. Define the **v2 hierarchy and scope conventions** and add the subtrees v2
   needs imminently (fleet/IncusOS secrets).
3. Document the model (README + meta-repo ADR), including the
   **generated-durable exception**.
4. Remove artifacts superseded by other repos (stale tailnet policy).
5. Define (not necessarily deploy) the **per-scope CI decrypt** IAM pattern.

## Non-goals

- Moving or renaming any existing encrypted file — live consumers read these
  exact paths (Keycloak boot via `labctl`, VyOS Ansible, the
  `network/tailscale` tofu root). Path moves are a later, consumer-by-consumer
  effort.
- Secrets→Vault sync automation (T34, deferred).
- Rotating secret *values* (only re-wrapping data keys).
- Deleting the legacy `talos-platform` scope/file (glab platform cluster —
  its fate belongs to the T37 carry-forward audit).

## Facts

| Fact | Value |
| --- | --- |
| Repo | github.com/GilmanLab/secrets (checkout `~/code/glab/secrets`) |
| KMS key (never changes) | `arn:aws:kms:us-west-2:186067932323:key/2aba1d94-6eaf-4d80-8d26-2077f32fd7c5`, alias `alias/glab-sops`, managed by `GilmanLab/aws` root `aws/lab-foundation` |
| PGP recovery recipient | fingerprint `3965F16E293466CFE77D47F38C15553EEB22DB2A` — YubiKey-backed (offline master, subkeys on three YubiKeys, Josh sole holder) |
| Encryption context convention | `Repo: GilmanLab/secrets` + `Scope: <scope>` on every file (capitalized keys — existing repo convention) |
| AWS auth | profile `lab-admin` (SSO, MFA); CI later via GitHub OIDC roles rooted in `GilmanLab/aws` `aws/github-oidc` |

Current encrypted inventory (7 files, 4 scopes):

| File | Scope |
| --- | --- |
| `network/tailscale/terraform.sops.yaml` | `network-tailscale` |
| `network/vyos/dns/powerdns.sops.yaml` | `network-vyos` |
| `network/vyos/ssh.sops.yaml` | `network-vyos` |
| `network/vyos/tailscale.sops.yaml` | `network-vyos` |
| `services/keycloak/admin.sops.yaml` | `keycloak` |
| `services/keycloak/bootstrap.sops.yaml` | `keycloak` |
| `compute/talos/platform/cluster-secrets.sops.yaml` | `talos-platform` |

Also present and **stale**: `network/tailscale/policy.hujson` +
`.github/workflows/tailscale-acl.yml` — superseded by session 003, which made
`GilmanLab/networking` the canonical policy home (meta-repo ADR-0002).

## Design to encode

### Key groups: KMS + PGP in ONE group

SOPS semantics matter here: recipients in the **same** `key_groups` entry are
alternatives (any one can decrypt); multiple groups mean Shamir (all groups
required). Recovery demands PGP-alone decryption when AWS is unreachable, so
every creation rule gets **one key group containing both** the KMS entry
(with its encryption context) and the PGP fingerprint:

```yaml
creation_rules:
  - path_regex: ^fleet/[^/]+/.*\.sops\.ya?ml$
    key_groups:
      - kms:
          - arn: arn:aws:kms:us-west-2:186067932323:key/2aba1d94-6eaf-4d80-8d26-2077f32fd7c5
            context:
              Repo: GilmanLab/secrets
              Scope: fleet
        pgp:
          - 3965F16E293466CFE77D47F38C15553EEB22DB2A
```

Consequence stated in the README: PGP bypasses IAM scoping by design; the
YubiKey is a break-glass path, custody is physical, and routine decryption is
KMS. (This is the explicit, documented reversal of glab's session-026
KMS-only rule.)

### v2 hierarchy

Existing subtrees stay put. New convention, top-level = consumer domain:

```
fleet/<node>/…        # per-machine IncusOS secrets — Scope: fleet
fleet/shared/…        # fleet-wide (e.g., seed client key) — Scope: fleet
clusters/<name>/…     # per-k8s-cluster — Scope: cluster-<name> (added per cluster)
services/<svc>/…      # hosted service creds — Scope: <svc> (keycloak exists)
network/…             # network devices/tailnet (existing scopes)
compute/…             # legacy glab; frozen pending T37
```

Add now: the `fleet` creation rule (secrets production is imminent — IncusOS
ZFS recovery keys, seed client private key). Add `clusters/` rules only when
the first cluster secret lands (one scope per cluster).

Scope granularity note: one scope per *access boundary*, not per file. A
future automation principal that should read only fleet secrets gets a grant
conditioned on `Scope=fleet` and can read nothing else.

### Generated-durable exception (document verbatim in README)

Non-generated secrets MUST live here (the GitOps mandate). Generated-but-
durable, lab-recovery-critical secrets (IncusOS ZFS `encryption_recovery_keys`,
the seed/bootstrap client private key, the image-factory cache-signing key)
also live here as a documented exception: they must survive the lab and
predate Vault. Ephemeral/generated-at-runtime secrets MUST NOT be committed.

### CI decrypt pattern (define now, instantiate on first consumer)

- IAM lives in `GilmanLab/aws` (new root, e.g. `aws/secrets-iam`), using the
  OIDC provider from `aws/github-oidc`.
- One role per consumer workflow; trust conditioned on the exact repo (and
  ideally `job_workflow_ref`); permissions = `kms:Decrypt` on the key ARN,
  **doubly conditioned** on `kms:EncryptionContext:Repo = GilmanLab/secrets`
  and `kms:EncryptionContext:Scope = <scope>` (the catalyst "grant
  invariant": an unconditioned grant spans every scope and is a defect).
- No long-lived AWS keys anywhere; humans use `lab-admin` SSO (MFA).
- Do NOT create roles speculatively — first real consumer (likely `fleet`
  seed rendering or the T34 Vault sync) instantiates the pattern.

## Phases

### Phase 0 — Verify and capture (read-only)

1. Fresh SSO: `aws sso login --profile lab-admin`; verify account
   `186067932323`. YubiKey NOT required for this phase.
2. Confirm every one of the 7 files decrypts today:
   `AWS_PROFILE=lab-admin sops -d <file> | sha256sum` — record plaintext
   hashes (hashes only; never write plaintext to disk).
3. Confirm `GilmanLab/networking` `tailscale/policy.hujson` is the live
   policy (per ADR-0002; console editing disabled) before touching the stale
   copy here.

### Phase 1 — `.sops.yaml` rewrite + rewrap

1. Rewrite creation rules: keep the four existing scope rules byte-compatible
   (same regex, same KMS+context) but add the `pgp` entry to each key group;
   add the new `fleet` rule (KMS `Scope: fleet` + PGP).
2. Rewrap: `AWS_PROFILE=lab-admin sops updatekeys -y` on each of the 7 files.
3. Known quirk: SOPS ≥3.11 serializes empty `aws_profile: ""` in KMS metadata;
   do not strip it manually (invalidates the MAC).
4. Verify, all 7 files:
   - KMS-only path: `SOPS_DECRYPTION_ORDER=kms sops -d` → sha256 matches
     Phase 0.
   - PGP recipient present: metadata lists the fingerprint on every file.
   - PGP-only decrypt: operator step WITH a YubiKey — decrypt at least one
     file per scope with AWS credentials absent (`AWS_PROFILE= sops -d` in an
     env without valid AWS auth). This is the break-glass proof; do not skip.

### Phase 2 — Hierarchy scaffold + documentation

1. Create `fleet/` (a `.gitkeep` or the first real secret if available —
   prefer real work over placeholders; if no fleet secret exists yet, the
   creation rule alone suffices and no empty dirs are committed).
2. README rewrite: the model (KMS routine / PGP break-glass), scope table,
   context convention, generated-durable exception, updatekeys procedure,
   the "never touch old-account state" style warnings do not belong here —
   keep it secrets-focused.
3. Meta-repo docs companion (required by AGENTS.md): **ADR-0003** in
   `docs/docs/decisions/` — "Secrets root of trust: AWS KMS with PGP
   recovery" — MADR format, recording the reversal of glab's KMS-only rule,
   the one-key-group semantics, the grant invariant, and the generated-
   durable exception. Update `mkdocs.yml` nav + index; `moon run docs:build`
   must pass. (Check `docs/docs/architecture/` for glab-era secrets pages
   only if present in the meta repo — v1 architecture docs live in glab's
   docs repo and are NOT ported here.)

### Phase 3 — Stale artifact removal

1. Remove `network/tailscale/policy.hujson` and
   `.github/workflows/tailscale-acl.yml` from `GilmanLab/secrets` (canonical
   home is `GilmanLab/networking` per ADR-0002). Verify the networking
   workflow is green/live first (Phase 0 step 3).
2. Check `.sops.yaml` needs no rule change for this (policy.hujson was never
   SOPS-encrypted; it does not).

### Phase 4 — Repo hygiene

1. `.github/repository-settings.toml` / branch protection: confirm squash-only
   and PR flow match org norms (repo predates some conventions).
2. CI (`.github/workflows/ci.yml` + Moon): add a check that fails if any
   `*.sops.yaml` lacks the PGP recipient or carries a wrong/absent encryption
   context (cheap guard: parse SOPS metadata; no decryption needed, no AWS in
   CI).

## Acceptance

- All 7 existing files: KMS-path plaintext hash unchanged from Phase 0.
- Every encrypted file's metadata carries both the KMS entry (correct
  context) and PGP fingerprint `3965…DB2A`.
- At least one PGP-only decrypt proven per scope with a YubiKey and no AWS.
- `fleet` creation rule present; a test encrypt/decrypt round-trip under
  `fleet/` passes with the right context (use `--filename-override`, then
  discard).
- Stale policy artifacts gone; networking's policy workflow unaffected.
- ADR-0003 merged in the meta docs site (`moon run docs:build` strict-pass).
- Report back to session 002: verification table, deviations, whether any
  fleet secret was actually created.

## Risks

- **Breaking live consumers by moving files** — forbidden in this pass;
  Keycloak's boot path (`labctl` → `services/keycloak/*`), VyOS Ansible
  (`network/vyos/*`), and the tailscale tofu root read current paths.
- **MAC invalidation** via manual metadata edits — only `sops updatekeys`
  touches wrapped keys.
- **Plaintext leakage** during verification — pipe to `sha256sum`, never to
  files; no plaintext in command args or CI logs.
- **PGP verify theater** — the break-glass proof must run with AWS auth
  genuinely absent, else it proves nothing.
- **Scope drift** — new rules must keep `Repo`/`Scope` capitalization
  (existing convention); a mismatch silently creates a second context
  vocabulary and breaks future IAM conditions.
