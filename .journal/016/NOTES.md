---
id: 016
title: Session opened, goal pending
started: 2026-08-25
---

## 2026-08-25 11:14 — Kickoff
Goal for the session: not yet stated; the user asked to start a new session and
has not given the actual request.
Current state of the world: four-node Incus cluster live (nas01 + lab01–03);
storage fully converged via `fleet/cluster` pyinfra; T48 (VLAN 30 lab datapath)
still blocked on the IncusOS stable release carrying lxc/incus-os#1306 — newest
published build remains `202608201218`. Sessions 011, 012, 014, 015 are open in
parallel. Open threads from 013: sw-core01 `just plan` after next
`aws sso login`, svc-tofu RouterOS password rotation, T44–T47.
Plan: await the user's request.

## 2026-08-25 11:32 — Goal stated: core-services placement assessment
Josh's actual ask: assess the VISION's management-cluster design — core services
(Vault, SPIRE, Zitadel, CAPI) in a platform k8s cluster vs separate VMs.
Availability argues for k8s (nodes spread across lab01–03; Incus VMs cannot
migrate, no shared storage). Counter-worry: k8s placement makes one-off VMs
second-class citizens. Context reviewed: VISION compute-platform section
(mgmt cluster [DECIDED], 3 VMs on nas01; T21 stretch deferred; T32 lean CAPI
pivot), and ~/code/componere/incus-spire-attestor (SPIRE nodeattestor pair for
Incus VMs, v1 architecture in that repo's journal 001/ARCHITECTURE.md —
nonce-in-instance-config challenge, server plugin needs Incus API client cert
with can_edit).

## 2026-08-25 11:41 — Assessment delivered; enumerating remaining platform-cluster work
Delivered placement assessment: cluster exists regardless (CAPI); availability
argument really = stretch across lab01–03, not k8s per se; second-class-VM risk
is an interface-layer problem (guardrail: every platform service consumable
from a plain VM; incus-spire-attestor is that pattern for identity). Rec: start
Vault in-cluster on local PVs + anti-affinity with a cheap eject path.
Next: work breakdown for initial platform cluster deploy (bootstrap steps 3–4).

## 2026-08-25 22:38 — T32 spike executed: verdict (b) CAPI self-managed pivot
Ran the full spike on sandbox01 (Incus 7.3, clustered single-node + HTTPS API
for CAPN). Stack: kind, clusterctl v1.13.3/CAPI v1.14.0, CAPN v0.9.0 (v1beta2,
supports Incus 7.x — newer than the 08-14 research), CABPT v0.6.12 / CACPPT
v0.5.13, Talos v1.12.2 nocloud (factory image), k8s v1.34.0.
Results: 3-CP Talos cluster Ready ~3.5 min; forward pivot 2.3s; post-pivot
self-reconciliation proven (scaled MD 0→1→0, cluster created its own worker
VM); reverse pivot worked first try; clean teardown. Only failure all spike:
JSON6902 configPatches rejected for multi-doc Talos configs → strategicPatches.
UEFI-boot caveat from the CAPN book did NOT manifest. lxc-secret carries a
full-trust Incus client cert in etcd — custody consideration for the real
cluster. Dev haproxy LB is a SPOF: production = kube-vip (fits no-BGP ruling).
Recorded: .journal/016/SPIKE_T32.md, T32_CLUSTER_MANIFEST.yaml; VISION T32 →
resolved, VM-orchestration section updated. Residue on sandbox01 documented in
the spike report (reset-button covers it).
