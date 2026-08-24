---
id: 013
title: Review the 25G DAC issues on the lab nodes
started: 2026-08-23
---

## 2026-08-23 17:45 — Kickoff
Goal for the session: start a new session, then recover the prior-session
detail on the problems hit with the 25G DAC cables running from the three
MS-02 lab nodes (lab01–03) to `sw-core01`.

Current state of the world: session 010 converged VLAN 30 (`10.10.30.0/24`,
L2-only) on `sw-core01` and on all four cluster nodes, but the lab datapath
is dead switch→host at the PHY. Tracked as T48. Two contributing causes were
identified: IncusOS ships no ice DDP package, so the E810-XXV NICs run in
Safe Mode, and the 25G DACs forced to 10G mis-negotiate FEC (RS-FEC
requested). Upstream fix `lxc/incus-os#1306` is merged and awaiting a release;
6x 10G-rated SFP+ DACs were expected ~2026-08-24. nas01's plain 10GbE path
works end to end.

Plan: read the session 010 diagnostic arc and the VISION T48 entry, and
report the specific DAC/FEC findings.

## 2026-08-23 18:05 — T48 retest after the 10G DAC swap: FEC fixed, RX still dead
Josh replaced all six 25G DACs with 10G DACs. Retested per the 010 handoff.

Media/PHY — FIXED:
- `sw-core01` ports 1–6 all report `status=link-ok rate=10Gbps`,
  `auto-negotiation=done`, SFP part `SFP-H10GB-CU3M` (OEM). Port 7 (nas01)
  unchanged at `SFP-10G-T`.
- lab01 kernel log at the swap (08-23 17:35–17:37): `ice … NIC Link is up
  10 Gbps Full Duplex, Requested FEC: NONE, Negotiated FEC: NONE, Autoneg
  Advertised: Off`. Pre-swap the same lines read `Requested FEC: RS-FEC,
  Negotiated FEC: NONE`. The FEC mismatch is gone.
- Lab bond members now show non-zero `rx_bytes` for the first time
  (~1.14 MB each, was literally 0), so the PHY is no longer stone dead.

Datapath — STILL DEAD switch→lab:
- Test rig: four Alpine containers (`t30-<node>`, macvlan on `fast30`,
  10.10.30.221–224), deleted afterwards.
- Full 4x4 ping mesh on VLAN 30: 100% loss on every pair.
- lab01→nas01 direction WORKS: tcpdump inside `t30-nas01` captured
  `ARP Request who-has 10.10.30.221 tell 10.10.30.222` plus the replies;
  200x1200B burst = lab01 fast tx +248,526, nas01 fast rx +249,389.
- nas01→lab01 direction DEAD: same burst = nas01 fast tx +248,400,
  switch `sfp-sfpplus1` **tx +251,185**, lab01 fast rx **+0**. Same for
  lab02 (+218) and lab03 (+70) against ~124,000 bytes sent. tcpdump in
  `t30-lab01` captured zero frames, including broadcast ARP.
- Switch bridge host table on VID 30 has learned all four node MACs and all
  four container macvlan MACs, each on the right port — switch-side learning
  and forwarding are correct.
- Idle 60s baseline: switch port 1 tx 32 pkts / 2746 B, lab01 fast rx 436 B
  (≈2 LLDP frames). So a trickle of untagged multicast gets in and
  everything else — including all tagged VLAN 30 traffic — is dropped below
  the MAC.

Cause isolated to the SECOND fault, alone:
- `ice 0000:01:00.x: Direct firmware load for intel/ice/ddp/ice.pkg failed
  with error -2` → `Entering Safe Mode` is present in the CURRENT boot
  (single boot id; nodes have not rebooted, uptime ~2 days).
- All four nodes still run IncusOS `202608201218`; `os_version_next` empty,
  last update check 2026-08-23T21:55Z, `needs_reboot: false`.
  `https://images.linuxcontainers.org/os/` shows `202608201218` as the newest
  published build, so lxc/incus-os#1306 (merged 2026-08-22T05:04Z,
  `de271730`) has not shipped in an image yet.
- Conclusion: the DACs were necessary but not sufficient. T48's remaining
  blocker is exactly the missing ice DDP package; the FEC leg is closed.

Config still converged: `CI= moon run fleet-cluster:network` 4/4 no-change,
`fleet-cluster:storage` 18/18 no-change (fleet @ b2b13cd).

Incidental: raft roles have rotated — lab01 is now database-leader and nas01
is database-standby (TECH_NOTES records the original nas01-leader layout;
roles are dynamic, no action).

Hypothesis worth one cheap experiment before the release lands: LLDP
(untagged) arrives while every tagged frame dies, which points at broken
VLAN filtering in Safe Mode rather than a generic RX failure. Testing it
means temporarily making VLAN 30 untagged on one lab port (switch PVID +
host address on `fast`), i.e. a real config change in tofu + fleet seeds —
Josh's call, not done.

Next: wait for the IncusOS stable release carrying #1306, reboot, confirm
Safe Mode is gone, then rerun this exact test and close T48.
