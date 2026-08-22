---
id: 012
title: Make the MacBook and Mac Studio interchangeable work environments
started: 2026-08-22
---

## 2026-08-22 11:24 — Kickoff

Goal for the session: make Josh's MacBook and Mac Studio interchangeable work
environments, so either machine can pick up work with the same tooling,
configuration, and state. The lab is a candidate utility for achieving that
(e.g. shared services, storage, remote compute), not a mandated component.

Current state of the world:

- Lab v2 substrate is largely up: four-node Incus cluster (nas01 + lab01–03),
  encrypted `data` pools on every node plus nas01's 17.4TB `hdd` raidz1, VLAN 30
  storage network converged but with a lab-side datapath blocker (T48, awaiting
  10G DACs ~2026-08-24 and the merged IncusOS ice-firmware fix).
- Networking (gw01/VyOS, sw-core01/RouterOS+OpenTofu, sw-mgmt01) is under
  management; secrets root of trust is SOPS + KMS + YubiKey in
  `GilmanLab/secrets`; Tailscale policy is GitOps-managed in
  `GilmanLab/networking`.
- No existing workstation/dotfiles automation is recorded in TECH_NOTES.md —
  workstation parity appears to be greenfield for Lab v2.
- Open threads carried in: T44 (Operations Center spike), T45 (PiKVM default
  creds), T46 (secrets checkout path `~/code/glab/secrets`), T47
  (meshcommander disposition), T48 (lab fast-path), T49 (upstream pyinfra-incus
  ops), plus T16 object storage.

Plan (agile, prototype-first): inventory what actually differs between the two
Macs and what "interchangeable" must cover (tooling, dotfiles, secrets, dev
state, data, running services), pick the smallest thing that proves the model,
build it, then decide whether the lab hosts anything durable. Avoid designing a
full workstation-management architecture up front.
