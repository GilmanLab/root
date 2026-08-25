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
