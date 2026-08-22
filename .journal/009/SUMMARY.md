---
id: 009
title: Bring the lab compute nodes online
date: 2026-08-21
status: complete
repos_touched: [GilmanLab/root, GilmanLab/fleet, GilmanLab/networking, GilmanLab/secrets]
related_sessions: [001, 006, 008]
---

## Goal

Execute bootstrap step 2: configure out-of-band access on the three MS-02
lab nodes and install IncusOS on them, joining each to the `nas01` cluster.
NAS storage work (T19) was explicitly deferred; Operations Center was
explicitly deferred to a later spike.

## Outcome

The goal was met. The Incus cluster is four nodes, all ONLINE: `nas01`
(database-leader), `lab01` and `lab02` (database voters), `lab03`
(database-standby) — the intended 3-voters-plus-standby topology. Every node
was fingerprint-verified before trust, had its recovery keys escrowed before
joining, and passed a targeted container smoke test. AMT is provisioned and
verified on all three nodes as their primary OOB path. Nine PRs merged across
four repositories; the procedure is captured in a new commissioning runbook.

## Key Decisions

- Bring nodes in via the proven post-boot API join, not Operations Center
  first -> OC is young (v0.81), its seeding/update ownership collides with
  the decided fleet/incusos-builder model, and the IncusOS provider is
  runtime-switchable so deferral costs nothing (tracked as T44).
- Lab management addresses are static-in-seed (MAC-bound), and AMT addresses
  are static-in-MEBx, not DHCP reservations -> Josh's call, superseding my
  initial reservation ruling: OOB must survive a gw01 outage, and the v1-era
  reservation MACs were never observed live. Dead reservations removed from
  gw01 at source and the address plan amended.
- Install media is USB (`type: raw`), definitively -> AMT IDER/USB-R boot
  reproducibly wedges the MS-02 firmware (AMI 2.22.0059): black video, dead
  local+remote input, only a cold AMT power cycle recovers. Everything else
  AMT does (KVM, SOL, power) works and is now the routine node-ops path.
- `force_install: true` in the lab seeds -> all three nodes carried old OS
  installs; the `install.target` selector still pins the 128GB drive. nas01's
  seed deliberately keeps it unset as a safety property.
- Recovery keys escrowed and retrieval acknowledged before every join ->
  join-then-escrow risks a locked-out node; the acknowledgment must use the
  dedicated `:retrieved` action endpoint (a state PUT is silently ignored).
- MeshCommander (not MeshCentral) as the AMT gateway, in a nas01 container ->
  disposable commissioning hand-tool vs a second standing management server
  days before evaluating OC; placement on VLAN 10 is REQUIRED because gw01's
  home->OOB path drops the AMT service ports.

## Changes

- `GilmanLab/fleet/nodes/lab0{1,2,3}/config.yaml` - seed configs: static
  .11/.12/.13 bound to verified MACs, `apply_defaults: false`, seeded
  bootstrap-admin cert, force_install, raw media, release pinned to the
  cluster's running `202608201218`.
- `GilmanLab/networking/vyos/gw01/config.boot.tmpl` - removed the three dead
  `lab0N-amt` DHCP static-mappings; deployed via the guarded sync.
- `GilmanLab/secrets` - `fleet/lab0N/amt.sops.yaml` (MEBx credentials, later
  synced to Josh's typed values) and `fleet/lab0N/incusos.sops.yaml`
  (LUKS + ZFS pool recovery keys) for all three nodes.
- `GilmanLab/root/docs` - new runbook `commission-lab-node.md` (MEBx/AMT,
  Secure Boot recipe, MAC harvest, USB install, rescue wipe, escrow, API
  join); address-plan amendment for static allocation semantics.
- Live: three MS-02s with AMT provisioned (TLS-only, consent NONE), IncusOS
  Secure Boot keys enrolled, IncusOS installed, joined; `meshcommander`
  container on nas01 (credential-less, systemd, proxied at
  `10.10.10.14:3000`); nas01's 008-era "recovery keys not retrieved" warning
  reconciled (escrow hash-verified, flag acked).
- `.journal/VISION.md` - T43 (this work) resolved; T03 resolved (AMT is the
  lab OOB path); T01/T06 updated; new T44 (OC spike), T45 (PiKVM cred
  rotation), T46 (secrets checkout consolidation), T47 (meshcommander
  disposition); bootstrap steps 1-2 marked done.

## Open Threads

- T44: Operations Center spike (post-install registration + existing-cluster
  adoption) before the fleet grows again.
- T45: pikvm01 still runs default admin/admin web credentials.
- T46: the secrets checkout lives at the v1-era `~/code/glab/secrets` path;
  consolidation proposal recorded (Josh may veto).
- T47: meshcommander container disposition — kept credential-less as the
  VLAN-10 AMT gateway for now.
- T01 remainder: ATX not wired; kvm01 channel-switch control (PiKVM HID
  hotkeys don't reach the TESmart — it sits on a pass-through hub port;
  re-plug or RS232); kvm01 input map still undocumented (T02).
- lab nodes' SFP+ links and nas01's 10GbE remain roleless pending the
  storage/workload network design; the 2TB data drives are untouched.
- Transcript exposures accepted by Josh: nas01's ZFS pool recovery key (my
  redaction slip) and the lab01 AMT password (MeshCommander edit dialog);
  rotate at will.

## Lessons

- AMI "Factory Key Provision" silently re-installs factory Secure Boot keys
  on every reset while in Setup Mode; it must be disabled before the key
  clear or IncusOS media keeps failing validation.
- The MS-02s expose a stable pattern: management 10GbE MAC = AMT MAC + 1.
  Verified on all three via lease or PXE-entry reads — but always verify
  (`strict_hwaddr` with a wrong MAC leaves the node unreachable, no shell).
- AMT >= 16 is TLS-only (16993/16995); 16992 staying closed is not a fault.
  MeshCommander's IDER streams from the browser tab (a reload kills the
  session), and modern AMT resets cost a multi-minute "KVM FW" wait before
  video returns.
- Old-OS remnants can fail the IncusOS installer with
  `mkfs.vfat ... contains a mounted filesystem` (seen with Proxmox);
  the fix is a rescue-stick `wipefs`/`sgdisk` of the target disk only.
- The BIOS network-stack PXE entries are a clean firmware-level MAC harvest
  for blank machines; the UEFI shell is useless for this (no NIC drivers).

## References

- [fleet#2](https://github.com/GilmanLab/fleet/pull/2) lab node seed configs
- [networking#13](https://github.com/GilmanLab/networking/pull/13) dead AMT reservations
- [secrets#29](https://github.com/GilmanLab/secrets/pull/29) AMT credentials
- [secrets#30](https://github.com/GilmanLab/secrets/pull/30) AMT password sync
- [secrets#31](https://github.com/GilmanLab/secrets/pull/31) lab01 recovery keys
- [secrets#32](https://github.com/GilmanLab/secrets/pull/32) lab02 recovery keys
- [secrets#33](https://github.com/GilmanLab/secrets/pull/33) lab03 recovery keys
- [root#22](https://github.com/GilmanLab/root/pull/22) commissioning runbook + address plan
- `docs/docs/runbooks/commission-lab-node.md`
- `.journal/008/SUMMARY.md` (nas01 bootstrap), `.journal/VISION.md` (T43)
