---
id: 010
title: New lab work session
started: 2026-08-21
---

## 2026-08-21 17:25 — Kickoff
Goal for the session: not yet stated; the user asked to start a new session and
will provide the actual request next.
Current state of the world: session 009 closed today with the four-node Incus
cluster live (nas01 leader; lab01/lab02 voters; lab03 standby), AMT provisioned
on all three MS-02s, recovery keys escrowed, and the commissioning runbook
merged (root#22). Open threads from 009: T44 (Operations Center spike), T45
(PiKVM default creds), T46 (secrets checkout consolidation), T47
(meshcommander disposition), storage/workload network design pending (T19
deferred).
Plan: await the user's request, then update this entry with the concrete goal.

## 2026-08-21 17:35 — Goal stated + live survey
Goal: configure storage and networking correctly across all four cluster
nodes (nas01 + lab01–03), starting with nas01.
Live survey (via nas01: remote, bootstrap-admin):
- Cluster: 4 nodes ONLINE (nas01 leader; lab01/02 database; lab03 standby).
- Storage: only `local` zfs pool per node on the OS drive (nas01 usable
  ~91GB). nas01 data drives blank: 2x WD_BLACK SN7100 1TB (nvme0n1/nvme1n1).
  lab01: blank Samsung 990 EVO Plus 2TB. Scrub schedule preset `0 4 * * 0`.
- Network: every node has a single `mgmt` interface (roles
  management+cluster) on VLAN 10, linked at 2.5G through sw-mgmt01. Fast
  links all UNCONFIGURED and link-down: nas01 eno1 10GbE (38:05:25:37:8d:7b,
  sw-core01 port 7), lab01 eno1np0/eno2np1 E810-XXV 25G (…:32:de:f3/f4,
  sw-core01 ports 1–2). Only network: default NAT incusbr0.
- sw-core01 ports 1–7 awaiting role assignment per address plan (docs say
  membership comes with the compute-network design = this session).
Next: put design options to Josh (nas01 pool layout, WD Reds/T19 timing,
LACP vs single link, L2-only cluster/storage VLAN).
