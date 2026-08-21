---
id: 002
title: Lab v2 vision, tracker, and first-node bootstrap
date: 2026-08-20
status: complete
repos_touched: [GilmanLab/root, GilmanLab/fleet, GilmanLab/secrets]
related_sessions: [001, 003, 004, 005, 006, 007]
---

## Goal

Act as Josh's sounding board to capture the Lab v2 vision into a durable
working document other agents can build from, resolve the holes and
inconsistencies it surfaced, and drive the resulting work — by handoff plan or
directly. The session grew from "help me stop repeating myself" into the
program office for the v2 build-out, and finished by bootstrapping the lab's
first compute node live.

## Outcome

Goal met and exceeded. The two headline artifacts:

1. **`.journal/VISION.md`** (promoted to the journal root at close) — the
   canonical vision-and-context document: lab purpose ("the personal on-prem
   cloud of a Senior SRE", colo-company design fiction), core principles
   (GitOps first; immutability/reproducibility), product-vs-instance split
   (componere/imgoci vs GilmanLab), the full compute/storage/secrets/AWS
   decisions, and the running **Tracker** (T01–T42) that this and sibling
   sessions worked from. Any future session should read it first and keep it
   current.
2. **A live Incus cluster.** `nas01` runs IncusOS `202608201218`, seeded from
   `GilmanLab/fleet`, cluster-enabled (member `nas01`, database-leader,
   ONLINE), container-smoke-tested, reboot-survival-proven with TPM
   auto-unseal, recovery keys escrowed.

Work this session executed directly: naming registry + docs sweep (root#8),
sw-mgmt01's first-ever configuration (factory→VLANs 10/70, live via browser
through a gw01 tunnel), nas01 NIC-swap discovery and correction, the fleet
repo + nas01 seed config, three secrets escrows, and the full install
including recovery from a TPM-unseal failure. Work driven via handoff plans
executed by sessions 004 (AWS migration), 005 (secrets restructure), and
007 (sandbox01), with results verified and absorbed here.

## Key Decisions

All recorded with rationale in `.journal/VISION.md`; the majors:

- Canonical role-based device naming (`gw01`, `nas01`, `sandbox01`, …) →
  docs/registry/system-identity all speak one vocabulary.
- Compute: one 4-node IncusOS Incus cluster (lab01–03 + nas01); Talos k8s
  clusters as VMs, EKS-style cattle plus one specified management cluster on
  nas01 (Zitadel, Vault, CAPI); no hyperconverged storage — local NVMe +
  k8s-layer replication.
- Tinkerbell and iPXE rejected (homogeneous IncusOS fleet has no netboot
  path; AMT/seeded media + factory-reset API cover the loop); Sidero
  image-factory adopted (self-hosted, later) over a bespoke Talos builder.
- IncusOS images are never published: config in git, single-step local
  build+burn via componere's `incusos-builder`; reproducibility lives in the
  pinned recipe.
- Secrets root of trust: AWS KMS (`alias/glab-sops`) + YubiKey PGP recovery —
  a conscious reversal of glab's KMS-only rule (ADR-0003); scope-per-boundary
  contexts; generated-durable recovery material is escrowed in the secrets
  repo by documented exception.
- AWS substrate carried forward from glab (v1) into `GilmanLab/aws` with
  state preserved; Zitadel replaces the live Keycloak (teardown deferred).
- Repo boundaries: `fleet` = bare-metal instance config only; `sandbox` =
  the deliberately-mutable exception box; k8s repos come later.

## Changes

- `.journal/VISION.md` — created, grown across the session, promoted to root.
- `GilmanLab/root` — naming registry + sweep (#8), AWS repo bootstrap in
  `init.sh` (#11, via session 004), fleet in `init.sh` (#17), tailscale
  trust-subject fix absorbed (#10, session 003), `runbooks/rebuild-nas01.md`
  (#18), ADR-0003 (#12, via session 005).
- `GilmanLab/fleet` — created: nas01 IncusOS seed config (MAC-bound static
  mgmt addressing, size-targeted install disk, bootstrap client trust),
  pinned-builder CI (#1). Default branch fixed to `master`.
- `GilmanLab/secrets` — bootstrap client escrow (#24), `network-sw-mgmt01`
  scope + switch admin credential (#25), nas01 LUKS + ZFS recovery keys (#26).
- Live infrastructure — `sw-mgmt01` configured and reboot-persistent; nas01
  cables corrected (10G NIC → sw-core01 @10G, 5G NIC → sw-mgmt01 @2.5G);
  nas01 installed and clustered; glab-era IncusOS remnant wiped with consent;
  fTPM cleared.
- Handoff plans (remain in `.journal/002/`): `AWS_MIGRATION_PLAN.md`,
  `SECRETS_RESTRUCTURE_PLAN.md`, `SANDBOX_SETUP_PLAN.md`,
  `NAS_BOOTSTRAP_PLAN.md` — all executed (sessions 004/005/007 and this one).

## Open Threads

The Tracker in `.journal/VISION.md` is authoritative; the live ones at close:

- **T32 — CAPI-pivot spike** on `sandbox01` (ready, idle): decides tofu vs
  CAPI for the management cluster's VMs. The tip of the build-out.
- **Step-3 deploy mechanism** for the critical services (Zitadel/Vault/CAPI)
  is still only in Josh's head; T22 (Flux vs Argo) rides with it.
- lab01–03: batch repeats of the runbooked nas01 procedure, gated on AMT
  provisioning (T03) or USB; T01 OOB pass remainder (**wire the PiKVM ATX
  cable**; kvm01 channel-switch control; other inputs).
- T04/T05 (UPS card + load test), T07 (gw01 Port 1 purpose), T02 (console
  cabling reference doc), T40 (Tailscale console edit-lock check).
- T10 (cluster IPAM/LB — first consumer brings BGP design), T31 (image
  factory deploy), T24 (Vault cold-start/DR), T34 (secrets→Vault sync).
- T16 Garage/backup story, T19 bay drives, T21 mgmt stretch, T37 glab
  carry-forward audit, T38 Keycloak teardown (after Zitadel), T39 timed
  AWS-migration scratch/state cleanup.
- Micro-residuals: `encryption_recovery_keys_retrieved` still `false` on
  nas01 (cosmetic console warning; acknowledge mechanism TBD); PXE-ROM DHCP
  OFFERs unanswered by Kea while real clients lease fine (curiosity);
  recovery keys transited this session's transcript — rotate via the
  security API if that ever matters; nas01's two 1TB drives are blank and
  unassigned pending storage design.

## Lessons

- IncusOS + fTPM: a TPM with prior history makes first boot demand a recovery
  key that doesn't exist yet. Clear the fTPM before installing on
  previously-used hardware (now in the rebuild runbook).
- Never write IncusOS install media to an internal drive: PCR4-measured boot
  path + a permanent rogue boot entry. Removable media exists for a reason.
- The PiKVM HID path through the TESmart is production-grade (it drove an
  entire OS install); the MSD path is not (USB 1.1 enumeration).
- BIOS NIC labels and port guesses lie; `ethtool` from a live session is
  ground truth. The N5 Pro's "5GbE vs 10GbE" cabling was inverted.
- A switch that has never been configured looks exactly like a broken VLAN
  design. Check the trunk's untagged-frame drop counters early.

## References

- `.journal/VISION.md` — the vision + tracker (read first).
- PRs this session: root#8/#17/#18, fleet#1, secrets#24/#25/#26.
- Executed-by-siblings: `.journal/004/SUMMARY.md` (AWS), `.journal/005/SUMMARY.md`
  (secrets), `.journal/007/SUMMARY.md` (sandbox01); context from
  `.journal/001`, `.journal/003`, `.journal/006`.
- Research transcripts: `history://IncusOsResearch`, `history://IncusSeedResearch`,
  `history://OldLabAwsAudit`, `history://GlabAwsMigrationAudit`.
- Meta docs shipped along the way: naming registry, ADR-0002 (via 003),
  ADR-0003 (via 005), address plan (via 006), `runbooks/rebuild-nas01.md`.
