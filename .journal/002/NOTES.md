---
id: 002
title: New session (goal pending)
started: 2026-08-14
---

## 2026-08-14 17:43 — Kickoff
Goal for the session: not yet stated; user requested a fresh session and will provide the task next.
Current state of the world: master at 3bcd8c0 (docs standardization PR #2 merged); session 001 (Lab v2 core networking) is in-progress in parallel; journal worktree at .wt/journal-jmgilman in sync with origin.
Plan: await the user's first request, then update this entry with the concrete goal.


## 2026-08-14 17:50 — Goal stated
Role: intelligent partner / sounding board. Capture Josh's homelab plan/vision
into a working document in this session folder (.journal/002/) that other
agents can use as shared context during lab build-out. Pain points driving
this: constant repetition across agents, and holes/inconsistencies surfacing
in the thinking itself. Free to research, spike, and probe assumptions.
Plan: iterative dump-and-refine sessions into a living doc; challenge
inconsistencies as they appear; keep structure light (agile, not waterfall).

## 2026-08-14 21:28 — Naming decided; docs PR #8 merged
Reviewed docs/ (inventory, ADR-0001, core-network draft, cabling map) and
seeded VISION.md in this folder. Josh resolved several holes: UM760 =
uncommissioned shelf spare; NAS 5GbE → TEG port 8; UPS mgmt card present but
unhooked (TODO); upstream-of-home-router docs deprioritized.
Decided: canonical role-based device names (gw01, rtr01, sw-core01, sw-mgmt01,
lab01-03, nas01, pikvm01, kvm01, ups01; UM760 unnamed until commissioned).
Shipped PR #8 (squash 3b9482a): new reference/naming.md, name sweep across
networking docs + design draft (ADR-0001 left untouched per MADR immutability),
PHY-019 added for nas01 5G link. Strict mkdocs build passed.
Next: continue vision dump — lab purpose and compute platform still [OPEN];
device-identity rollout (hostnames/labels) pending as implementation work.

## 2026-08-14 21:54 — Vision dump: purpose, compute, OOB; research folded in
Purpose decided: "personal on-prem cloud of a Senior SRE" — lab is the
product; foundation stable, workloads volatile; bleeding-edge welcome.
Compute decided: 4-node IncusOS cluster (lab01-03 + nas01); Talos k8s
clusters as Incus VMs, EKS-style cattle with a repeatable cluster template
as the investment priority; few one-off VMs; no hyperconverged storage —
local NVMe pools + k8s-layer replication (Longhorn-style); nas01 runs
storage-centric services (Garage) and is accepted as more critical.
OOB: kvm01 wired to lab01-03/nas01/gw01, pikvm01 into kvm01 — untested.
Flagged: cold-move claim invalid for node *failure* (local storage dies with
the node) — proposed distributed Garage across all 4 nodes as alternative;
pikvm01/kvm01 network hangs off gw01 (dependency inversion, Wi-Fi fallback?).
IncusOsResearch brief (agent://IncusOsResearch) key facts folded into
VISION.md: IncusOS GA 2025-11, SB+TPM2 required, seeded ISO/IMG install (no
PXE, no SSH), Ceph-on-IncusOS unsupported until ~2026.09, OVN central not
hosted yet (bridge VLANs for now), Talos via nocloud + cloud-init disk
(CAPN template exists, not CI-tested, BIOS-boot gotcha), 4-node quorum a
non-issue. New opens: N5 Pro TPM/SB verification, install-media delivery
for nas01 (no AMT), secrets custody for recovery keys/seed certs, CAPN vs
OpenTofu machinery.
Next: Josh to answer Garage shape/backup, pikvm01 Wi-Fi fallback intent,
N5 Pro bays plan; then consider ADR-0002 draft.

## 2026-08-14 22:04 — Tracker established; Josh's answers recorded
Josh asked the agent to own item tracking (too many parallel threads).
VISION.md holes list restructured into a Tracker table (T01–T19) with
statuses open/in-progress/deferred/resolved.
Answers: Garage + critical-data backup story deferred entirely (T16).
pikvm01 break-glass = local monitor/kb/mouse at the rack; gw01 network
dependency accepted (resolved). nas01 bulk capacity: 5x ~3TB WD Red from old
Synology going into the five bays, old RAID to be wiped when ready (T19).
Seeding/bootstrap (T14) is Josh's chosen next deep-dive: spawned
IncusSeedResearch (seed schemas, image production/CI, cert story, cluster
bootstrap sequencing, network pre-seeding, AMT delivery, Operations Center
maturity, reseeding). Results to fold into VISION.md and likely a bootstrap
design draft.

## 2026-08-14 22:17 — Management cluster, critical services, bootstrap flow
Josh revised: one specified cluster after all — Talos management cluster,
3 VMs on nas01, hosting critical services: Zitadel (identity), Vault
(secrets/PKI), Tinkerbell (provisioning), CAPI (the EKS mechanism, GitOps-
driven). Likely later stretch onto lab01-03; explicitly not designed yet.
Core principles recorded: GitOps first; immutability + reproducibility.
Bootstrap sequence (provisional): IncusOS on nas01 → 3 Talos VMs → critical
services → Tinkerbell provisions lab01-03 → CAPI spawns future clusters.
T09 resolved: CAPI. New: T20 Tinkerbell→IncusOS delivery tension (no PXE
path documented; SB key enrollment may break HookOS netboot), T21 mgmt
stretch (deferred), T22 GitOps engine + Git home, T23 Tinkerbell DHCP/PXE
network needs (session 001 coordination), T24 Vault bootstrap/DR.
Accepted risk noted: mgmt cluster = single nas01 failure domain until
stretched.

## 2026-08-14 22:25 — Seed research folded in (T14 resolved)
IncusSeedResearch brief (45KB, full text at history://IncusSeedResearch)
distilled into VISION.md "Seeding & install mechanics". Headlines: seed =
tar in seed-data partition, strict YAML schemas (install/applications/
incus-InitPreseed/network/update/kernel/security/provider/services/certs);
official headless injection via flasher-tool --image --seed (CI-able, pin
checksums); 4 images from one template set with per-node network.yaml
(MAC-bound, static addrs; bootstrap apply_defaults:true, joiners false);
post-boot cluster enable/join is the blessed path; AMT virtual CD for
MS-02s (force_reboot:false), USB IMG for nas01; encryption recovery keys
seedable (T15 shape: generate → seed → Bitwarden); factory-reset API =
rebuild-from-seed loop without media. OC v0.8.1 assessed too heavy for
one-time 4-node bootstrap.
T14 resolved. T12 sharpened (install.target in seed). T20 reframed: with
factory-reset + AMT reinstall, Tinkerbell may not earn its critical seat —
Josh to re-justify or drop.
Next: Josh reacts to bootstrap sketch; then draft designs/drafts bootstrap
design + likely ADR-0002.

## 2026-08-14 22:36 — Colo frame; image factory intent; Tinkerbell verdict pending
Josh's design fiction captured in VISION.md purpose: "medium company leaving
AWS for a colo bare-metal cloud"; new-machine onboarding must have a good
answer; bare metal is IncusOS-only (homogeneity load-bearing).
Josh intends a bespoke image factory (config → seeded ISO) — T25 opened with
design sketch (thin wrapper on flasher-tool, Go + upstream seed API types,
deterministic tar, render-time secrets, CLI-first).
T20 updated: recommended dropping Tinkerbell (homogeneous fleet + factory-
reset/AMT cover the loop; OC is the vendor-native MaaS path at scale);
awaiting Josh's ruling. T23 moot if dropped.

## 2026-08-15 12:43 — Product/instance split revealed (componere & imgoci)
Josh disclosed ~/code/componere (generalized OSS cloud product; GilmanLab =
that product on his hardware) and ~/code/imgoci (OS-image releases in OCI
registries). Surveyed both meta-repos: componere/incusos-builder in active
dev (vendors upstream incus-os mkosi tree) = the image factory; incus-vm-oci,
incus-bootc, componere/imgoci still template scaffolds (roles presumed,
unconfirmed). imgoci/spec = draft release-format spec (CUE + conformance);
bigoci = mature chunked large-file OCI transfer lib (~v0.1.0); go-oci-blob
lower-level; imgoci/go = canonical impl, early.
VISION.md: new "Product vs. instance" section with agent implication (image
build/distribution belongs product-side; lab consumes). T25 → in-progress,
product-side. T26 opened: product/instance boundary + interim-manual vs
block-on-product bootstrap ruling.