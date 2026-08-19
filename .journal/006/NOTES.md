---
id: 006
title: New session (goal pending)
started: 2026-08-18
---

## 2026-08-18 19:18 — Kickoff
Goal for the session: Start a new session; the substantive goal has not been stated yet.
Current state of the world: The personal journal is initialized on `journal/jmgilman`, and sessions 003–005 are closed with their durable context captured in `TECH_NOTES.md`.
Plan: Record the developer's first substantive request, inspect the relevant repository state, and execute it through the required isolated worktree and verification workflow.

## 2026-08-18 19:21 — Vision context loaded
Read session 002's `VISION.md` in full. It is background context only, not the assignment for session 006. Retain its confidence labels: rely on `[DECIDED]`, treat `[PROVISIONAL]` as changeable, and do not fill `[OPEN]` items by assumption.

## 2026-08-18 19:35 — Legacy VyOS audit
Compared the central core-network draft and VISION against `~/code/glab/infra/network/vyos/configs/gateway.conf`, then queried `gw01` read-only for interfaces, routes, firewall state, DHCP leases, containers, BGP, hostname, and DNS behavior.

The legacy substrate is reusable: `10.0.0.0/30` routed transit, the `10.10.0.0/16` lab envelope, VLAN 10 management, VLAN 40 workload reservation, VLAN 70 OOB, VyOS-owned gateways/NAT, Tailscale route advertisement, and the `glab.lol` DNS mirror all align with current direction. It is not reusable verbatim. VLAN 20/Tinkerbell, the UM760 bridge and BGP peers, persistent IncusOS artifact serving, live `bootstrap-k0s`, and hostname `gateway` are v1 state that conflicts with settled v2 decisions. The management-switch uplink is still described/configured as the UM760 link and does not carry VLAN 70, while the firewall is attached only to `eth0`, leaving inter-VLAN forwarding and non-`eth0` router input accepted by default.

Recommendation: retain the address envelope and proven transit, explicitly decide the surviving VLANs and network-service owners, write one canonical address/VLAN/port-membership reference, rework firewall attachments and stale services, then update and promote the core-network design. The current draft explicitly excludes the exact address/VLAN facts required to seed IncusOS nodes.
