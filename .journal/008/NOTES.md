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

## 2026-08-20 17:32 — sw-core01 live inspection (webfig via Chrome DevTools)
Confirmed: RouterOS 7.16.2 (stable) on CRS309-1G-8S+ (arm), serial HJK0ARX7PE0,
identity `lab-10g-switch`. Config is untouched v1. Full `/export` captured:
- Two bridges: defconf `bridge` (192.168.88.1/24, NO vlan filtering) holding
  ether1 + sfpplus5/6/7 ("LAB0x SAN"); `bridge-lab` (vlan-filtering) holding
  to-vyos(sfpplus8), spare-port1(sfpplus1), sfpplus2/3/4 ("LAB0x VM"),
  tagged-only.
- bridge-lab VLANs 10/30/40/50/60 (v1 names LAB_MGMT/PLATFORM/CLUSTER/
  SERVICE/STORAGE) all tagged on to-vyos + VM ports. v2 keeps only 10/40.
- mgmt: STATIC 10.10.10.2/24 on `mgmt-vlan10` (address-plan.md says DHCP
  reservation — mismatch), DNS + default route via 10.10.10.1.
- Services: www allowed from 10.10.10.1/32 only; www-ssl enabled, cert
  `crs309.mgmt.lab.gilman.io` (v1 domain — caused Chrome CN error), allowed
  from 192.168.1.0/24 + 10.10.0.0/16. REST API therefore already reachable at
  https://10.10.10.2/rest. Admin user only; no automation account.
- Hazard: nas01 10G is physically port 7 (= "LAB03 SAN") on the unfiltered
  defconf bridge with 192.168.88.1/24 — stray L2 touching nas01 storage NIC.
- Trunk to gw01 (port 8 "to-vyos") tags 10/30/40/50/60; gw01 v2 carries 10/40.
- Identity/time log noise: cloud time jump Aug/11→Aug/14 2026 (no NTP config
  in export; RouterOS cloud time active).

## 2026-08-20 17:36 — Direction decided: OpenTofu-managed sw-core01
User chose automation-first convergence (option 1) and explicitly chose
OpenTofu with terraform-routeros over extending the pyinfra pattern.
Spawned a software-architect agent to propose the architecture: repo/root
placement, state backend, provider auth + cert strategy, SOPS credential
flow, resource modeling (incl. defconf adoption/removal), in-band cutover
safety, operator-vs-CI apply model, and doc impacts.

## 2026-08-20 17:52 — Architecture proposal delivered
Software-architect agent delivered the sw-core01 OpenTofu architecture; saved
verbatim as `.journal/008/SW_CORE01_TOFU_ARCH.md`. Headline decisions: root at
GilmanLab/networking `routeros/sw-core01/` (one root per device), state in the
existing lab bucket (`networking/routeros/sw-core01.tfstate`), REST over
www-ssl with re-minted pinned self-signed cert (never insecure=true),
`svc-tofu` account with creds via SOPS -> ROS_* env vars (never TF vars/state),
import-block adoption of v2-kept objects + manual Safe-Mode purge of defconf/
v1 remnants, six-phase cutover that never modifies the mgmt path, operator
plan/apply with offline-only CI, docs updates incl. ADR-0004. Five open
questions pending user rulings (static-vs-reservation D1, ether1 role, winbox,
NTP, tailnet source check).
