---
id: 008
title: New Lab v2 work session
started: 2026-08-20
---

## 2026-08-20 17:17 — Kickoff
Goal for the session: not yet stated; the user asked to start a new session and
has not given the actual task. Awaiting their request.
Current state of the world: sessions 001–007 are all complete. `nas01` runs
IncusOS as the first cluster member, `gw01` runs the accepted VyOS
configuration, `sandbox01` base automation is live in `GilmanLab/sandbox`, the
secrets root of trust uses KMS + YubiKey PGP recovery, the tailnet policy is
GitOps-managed, and AWS roots live in private `GilmanLab/aws`.
Plan: record the user's goal when stated, then proceed per `.session.md` and
`.journal/VISION.md`.

## 2026-08-20 17:24 — Goal emerges: switch configuration + automation
Session scope is the network: `sw-core01` (MikroTik CRS309, never fully
configured, planned mgmt 10.10.10.2) and `sw-mgmt01` (TRENDnet TEG-3102WS,
hand-configured VLANs, still managed at factory 192.168.10.200; move to
10.10.70.2/VLAN 70 outstanding). Neither has automation.

Research findings (web, 2026-08-20):
- CRS309 dual-boots SwOS/RouterOS; boots RouterOS v7 by default. SwOS has NO
  API (web-only, scraping only). RouterOS v7 surfaces: REST API (www-ssl +
  cert; used by terraform-routeros, available on OpenTofu registry), SSH CLI
  with /export + Safe Mode (auto-revert on disconnect), binary API
  (librouteros), Ansible community.routeros. No commit-confirmed: changes are
  immediate; recovery = /system backup + export diff + Safe Mode.
- One RouterOS toolchain would also cover rtr01 and the CCR2004.
- Fit: sibling `networking_mikrotik` Python tooling in GilmanLab/networking
  (matches networking_vyos convention) over introducing OpenTofu on-prem.
- TEG-3102WS: no CLI/API. Web GUI + SNMP monitoring only; config
  backup/restore is an opaque config.bin over HTTP/TFTP (embeds credentials,
  firmware-coupled, not diffable). Proportionate path: documented desired
  state + scripted config.bin backup; treat as hand-managed appliance.

Next: user to pick direction (likely verify sw-core01 OS first).
