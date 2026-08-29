---
status: accepted
date: 2026-08-26
---

# ADR-0005: Anchor Internal PKI on the KMS Root with Sibling Intermediates

## Context and Problem Statement

The lab's internal PKI trust anchor is the offline-by-policy AWS KMS root CA
managed by the `security/pki/root-ca` root in `GilmanLab/aws`: the signing key
is generated inside KMS, never exported, and used only in explicit operator
ceremonies. Two internal issuers will hang beneath it: the HashiCorp Vault PKI
engine for internal server TLS, and SPIRE for workload identity. SPIRE will
run as a nested topology — a root SPIRE server on the management cluster
issuing intermediate CAs to downstream servers in each workload cluster.

The `root-ca` README originally sketched a linear chain, `Root (pathlen:2) →
Vault intermediate → SPIRE intermediate → SVID leaves`. That sketch predates
the nested-SPIRE decision and conflicts with it twice: nesting inserts a third
intermediate tier, which a `pathlen:2` root rejects during path validation,
and placing SPIRE beneath Vault couples SPIRE's certificate chain to Vault's
availability while Vault authentication is planned to depend on SPIRE — a
bootstrap and rebuild cycle. How should the internal CA hierarchy be shaped?

## Decision Drivers

- No dependency cycle between Vault and SPIRE at cold start or rebuild.
- Path validation must accommodate the nested SPIRE topology's chain depth.
- The root signing key must outlive any lab infrastructure, including the
  management cluster.
- Rebuilding the root SPIRE server should not force a lab-wide trust-bundle
  rotation.
- Signing events are rare; no standing service should hold CA authority.
- Minimize standing AWS infrastructure.

## Considered Options

- KMS root with sibling Vault and SPIRE intermediates
- Linear chain: root signs Vault, Vault signs SPIRE
- Root CA key stored in Vault, protected by backups
- Self-contained SPIRE trust domain with no upstream chain
- Standing online CA service (for example step-ca on EC2)

## Decision Outcome

Chosen option: **KMS root with sibling Vault and SPIRE intermediates**.

The KMS root remains the single internal trust anchor. Its certificate is
re-minted with the same KMS key and no path-length constraint; chain depth is
bounded at each intermediate when it is issued:

```text
Root CA (no path length constraint)
  -> cluster Vault intermediate pathlen:1
    -> internal TLS leaves
  -> SPIRE upstream intermediate pathlen:2
    -> SPIRE root server CA
      -> nested downstream cluster CAs
        -> workload SVID leaves
```

Both intermediates are signed directly by the root in `step` +
`step-kms-plugin` operator ceremonies; no standing CA service exists. The
SPIRE upstream intermediate is consumed through SPIRE's `disk`
UpstreamAuthority, with its private key custodied in `GilmanLab/secrets`
under the ADR-0003 recipient rules. Vault trusts SPIRE for authentication;
nothing in SPIRE's issuance path depends on Vault.

Certificates that browsers must trust use public ACME issuance against the
lab's public DNS zone. The private root never signs browser-facing
certificates.

The root certificate re-mint happens before either intermediate is issued,
while the root has no deployed consumers; the KMS key identity is unchanged
and only the certificate and its published fingerprint rotate.

### Consequences

- Good, because SPIRE and Vault bootstrap and rebuild independently; neither
  blocks the other's recovery.
- Good, because a rebuilt root SPIRE server re-signs under the same custodied
  intermediate, preserving the trust bundle without a lab-wide rotation.
- Good, because classic TLS clients validate everything internal against one
  installed root certificate.
- Good, because root signing authority exists only during ceremonies; there
  is no online CA to compromise or operate.
- Bad, because the SPIRE intermediate key exists as exportable material in
  `GilmanLab/secrets`, a step down from the root's KMS-only custody.
- Bad, because intermediate renewals are manual ceremonies that must be
  tracked before expiry.
- Bad, because the re-mint rotates the published root fingerprint once, and
  any early consumer of the old certificate must be updated deliberately.

### Confirmation

- `root_ca.crt` in `GilmanLab/aws` `security/pki/root-ca` carries
  `CA:TRUE` basicConstraints with no path-length constraint.
- Exactly two intermediates are issued directly by the root: the Vault PKI
  intermediate (`pathlen:1`) and the SPIRE upstream intermediate
  (`pathlen:2`).
- The SPIRE server configuration uses the `disk` UpstreamAuthority with the
  custodied intermediate; no `vault` UpstreamAuthority is configured.
- No CA service runs in AWS or the lab; certificate signing appears only in
  ceremony runbooks.
- Workload SVIDs chain leaf → downstream cluster CA → SPIRE root server CA →
  SPIRE upstream intermediate → root.

## Pros and Cons of the Options

### KMS Root with Sibling Intermediates

- Good, because it satisfies every driver with infrastructure that already
  exists.
- Bad, because two ceremony-managed intermediates mean two renewal schedules.

### Linear Chain (Root → Vault → SPIRE)

- Good, because Vault renewals could be automated through Vault itself.
- Bad, because SPIRE re-signing depends on Vault availability while Vault
  authentication depends on SPIRE — a cycle at cold start and rebuild.
- Bad, because the nested SPIRE chain exceeds the original `pathlen:2` root
  constraint.

### Root Key in Vault with Backups

- Good, because issuance could be fully online and API-driven.
- Bad, because the root of trust must outlive the management cluster that
  hosts Vault; coupling root custody to Raft snapshots and unseal-key
  recovery inverts that dependency.

### Self-Contained SPIRE Trust Domain

- Good, because it avoids the exportable intermediate key entirely.
- Bad, because SPIRE-server loss without a datastore restore mints a new
  root bundle, forcing a lab-wide trust rotation.
- Bad, because SVIDs cannot be validated against the lab root by non-SPIFFE
  consumers.

### Standing Online CA Service

- Good, because ACME automation could issue internal certificates on demand.
- Bad, because signing events are rare operator ceremonies; a standing
  networked service holding CA authority is attack surface without a
  workload. Online issuance needs are covered by Vault PKI and public ACME.

## More Information

- Root and ceremony details: `security/pki/root-ca/README.md` in
  [`GilmanLab/aws`](https://github.com/GilmanLab/aws).
- Custody rules for the SPIRE intermediate key:
  [ADR-0003](0003-use-kms-with-pgp-recovery-for-secrets.md).
- SPIRE nested topology and the Incus node-attestation chain were validated
  end to end in a manual spike (2026-08-26) using
  [incus-spire-attestor](https://github.com/componere/incus-spire-attestor)
  and
  [incus-guest-agent](https://github.com/componere/incus-guest-agent);
  the management-cluster SPIRE design will record the topology decision.
