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