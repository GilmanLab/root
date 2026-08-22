---
id: 010
title: Configure storage and networking across the cluster
date: 2026-08-21
status: complete
repos_touched: [GilmanLab/root, GilmanLab/fleet, GilmanLab/networking, GilmanLab/secrets, lxc/incus-os]
related_sessions: [002, 006, 008, 009]
---

## Goal

Configure storage and networking correctly across all four Incus cluster
nodes (nas01 + lab01–03), starting with the NAS. Mid-session Josh added a
standing mandate: all cluster configuration must be reproducible via
pyinfra-incus-style automation — no ad-hoc commands.

## Outcome

Storage: fully met. Encrypted `data` zpools on all four nodes (nas01 =
mirror of 2x 1TB SN7100, labs = single 2TB), cluster-wide Incus pool
`data`, and nas01's `hdd` bulk pool (zfs-raidz1, 4x 6TB WD Red Pro,
17.4TB usable, OS-level only). All keys escrowed and acknowledged; the
full storage deploy reruns 100% no-change.

Networking: configuration converged, datapath blocked by hardware/firmware.
VLAN 30 (`10.10.30.0/24`, L2-only) is live on sw-core01 (plain tagged
ports 1–7) and on every node (`fast`/`fast30`, active-backup bonds on the
labs, 10G links up, correct addresses). nas01's path works end to end.
The lab paths are dead switch→host at the PHY: IncusOS ships no ice DDP
firmware, so the E810s run in Safe Mode and request RS-FEC on 25G DACs
forced to 10G; frames die below the MAC. Upstream fix merged
(lxc/incus-os#1306); 10G-rated DACs are on order. Retest is pending both.

The GitOps mandate is fully implemented: `GilmanLab/fleet` now owns day-2
cluster convergence via the `cluster/` pyinfra project.

## Key Decisions

- Day-2 cluster automation lives in `fleet/cluster/` (pyinfra), not a new
  repo or OpenTofu -> fleet's charter already reserved runtime-config
  ownership; one repo per lifecycle of the same machines avoids
  seed↔runtime drift. Custom facts/ops fill pyinfra-incus 0.2.0 gaps
  (cluster `--target`, /os/1.0 APIs) lab-side first, upstream later (T49).
- Recovery-key escrow stays a runbook step; deploys assert the
  `:retrieved` flag and fail convergence until keys are escrowed -> the
  009 lesson enforced by machine without putting secrets in a converge loop.
- nas01 NVMe = zfs mirror; HDD = raidz1 4-wide -> nas01 is the accepted
  critical node; raidz expansion (supported, one device per resilver)
  absorbs the planned 5th drive, which mirrors could not.
- HDD pool is OS-level only -> Incus cluster pools must exist on every
  member; nas01-only pools are unsupported. Incus wiring waits for T16.
- VLAN 30 is L2-only with no gateway; Incus raft/API stays on VLAN 10 ->
  moving `cluster.https_address` requires a coordinated offline edit on
  all members, and bulk future traffic rides instance VLANs anyway.
- active-backup bonds instead of LACP -> LACP mux never converged because
  the hosts receive no LACPDUs (the same PHY fault); active-backup keeps
  failover with zero protocol dependency and no switch LAG.
- RouterOS 7.16.2 -> 7.24 upgrade kept although RouterOS was exonerated ->
  current stable plus the 7.17–7.19 bond/bridge fix window is the better
  baseline regardless.
- `vlan_tags: [30]` on the fast parent is mandatory -> IncusOS interfaces
  are internal VLAN-aware bridges; `vlan_tags` is the allow-list.

## Changes

- `fleet/cluster/` - new pyinfra project: /os/1.0 facts+ops (full-replace
  storage/network PUTs with confirmation-timeout + `:confirm`), cluster
  `--target` pool op, storage/network deploys, 29 behavioral tests, moon
  CI lane (fleet#3, #4, #5).
- `fleet/nodes/*/config.yaml` - seeds mirror runtime: fast/fast30,
  active-backup bonds, vlan_tags (reinstall reproducibility).
- `networking/routeros/sw-core01/` - VLAN 30 tagged on ports 1–7; LAGs
  added then removed (networking#14, #15); device on RouterOS 7.24.
- `secrets` - `zfs_pool_data_recovery_key` x4 (secrets#34) and nas01
  `zfs_pool_hdd_recovery_key` (secrets#35), hash-verified escrows.
- `root/docs` - address plan (VLAN 30, storage addresses, port roles) and
  core-network design amendments (root#23).
- Live: 3 pools on nas01, `data` on all labs, cluster pool `data`,
  VLAN 30 converged host+switch, RouterOS 7.24.
- Upstream: lxc/incus-os#1305 (issue), #1306 (fix, MERGED — app-build
  route per stgraber review).

## Open Threads

- **Incoming DACs (T48):** 6x 10G SFP+ DACs (SFP-H10GB-CU1M class) arrive
  ~2026-08-24. On arrival: swap the six lab SFP+ links at sw-core01
  ports 1–6, confirm 10G link with no FEC expectation, then retest —
  two containers with macvlan on `fast30` pinging across nodes, then
  `moon run fleet-cluster:storage|network` reruns (expect all no-change).
- **Upstream ice fix:** #1306 merged; waiting on the next IncusOS release
  to exit Safe Mode (stable channel, nodes check every 6h; reboot to
  apply). Either the DACs or the release may fix the datapath alone —
  verify which, then close T48.
- T44 (Operations Center spike), T45 (PiKVM creds), T46 (secrets
  checkout path), T47 (meshcommander) unchanged.
- T49: promote fleet_cluster ops upstream to meigma/pyinfra-incus.
- Instance/workload VLANs on the fast links: design with first consumer
  (T10/T11); ports carry only VLAN 30 today.
- Wipe endpoint UX: consider upstream issue for async/cancellable wipes
  and duplicate-request coalescing (queueing burned ~9h this session).

## Lessons

- IncusOS interfaces are internal VLAN-filtering bridges (`_p`/`_i`/`_v`/
  `_b` devices); `vlan_tags` on the parent is the VLAN allow-list and is
  required for tagged sub-interfaces to pass traffic.
- RouterOS `monitor` "active-ports" lies about LACP health; only
  `monitor-slaves` mux flags (Collecting/Distributing, Defaulted) show
  whether the data path is open.
- A link-up-TX-works-RX-dead pattern across identical hardware is a
  PHY/firmware systematic, not cabling: check driver state (Safe Mode)
  and FEC before touching switch config.
- `/os/1.0/system/storage/:wipe-drive` full-zeroes TRIM-less HDDs
  (~9h/6TB) synchronously; duplicate POSTs queue server-side behind a
  storage lock and survive client disconnects — never re-POST after a
  timeout, check `debug/processes` first. The same lock wedges `:reboot`.
- `incus query -d` takes literal data (no stdin form); non-secret
  payloads only.
- Minisforum N5 Pro bays hot-swap cleanly under IncusOS (detection and
  re-detection verified live).
- pyinfra-incus is Meigma-owned: lab-side gap-filling then upstream
  promotion is the intended flow (T26 pattern).

## References

- [fleet#3](https://github.com/GilmanLab/fleet/pull/3) cluster/ project + seed sync
- [fleet#4](https://github.com/GilmanLab/fleet/pull/4) active-backup + vlan_tags
- [fleet#5](https://github.com/GilmanLab/fleet/pull/5) nas01 hdd raidz1 pool
- [networking#14](https://github.com/GilmanLab/networking/pull/14) VLAN 30 + LAGs
- [networking#15](https://github.com/GilmanLab/networking/pull/15) drop LAGs, plain tagged ports
- [secrets#34](https://github.com/GilmanLab/secrets/pull/34) data pool keys
- [secrets#35](https://github.com/GilmanLab/secrets/pull/35) hdd pool key
- [root#23](https://github.com/GilmanLab/root/pull/23) VLAN 30 docs
- [lxc/incus-os#1305](https://github.com/lxc/incus-os/issues/1305) / [#1306](https://github.com/lxc/incus-os/pull/1306) ice DDP
- `.journal/010/NOTES.md` (full diagnostic arc), `.journal/VISION.md` (T48/T49)
- `.journal/009/SUMMARY.md` (commissioning), `.journal/008/SUMMARY.md` (sw-core01 tofu)
