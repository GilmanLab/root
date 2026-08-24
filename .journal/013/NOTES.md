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

## 2026-08-23 20:10 — Untagged experiment: stopgap is DEAD, unicast RX is broken
Josh approved the experiment. Ran it on lab03 only, all changes reverted.

Method (switch-side first, no host change): moved `sfp-sfpplus5/6` from the
VLAN 30 tagged list to the untagged list and set `pvid=30`,
`frame-types=admit-all` on both bridge ports. Test containers: `u30-nas01`
with macvlan on `fast30` (tagged, the proven-good side) and `u30-lab03` with
macvlan on `fast` (untagged). The switch does the tag translation, so the
lab03 host config stayed untouched for this phase.

Results, untagged into lab03:
- Broadcast RX **works**: `u30-lab03` captured nas01's broadcast ARP requests
  and a MikroTik UDP/5678 discovery frame, and its replies reached nas01.
  This is the first switch→lab frame delivery of the whole saga.
- Unicast RX **fails**: nas01's ICMP echo requests never appeared in the
  capture, while switch `sfp-sfpplus5` showed tx +125,186 bytes / 109 pkts
  for the burst and the container MAC was correctly learned on that port.
  `ip link set eth1 promisc on` in the container changed nothing.

So the tagged-vs-untagged split was only half the story. Phase two tested
whether the NIC's PRIMARY unicast MAC still works, since the macvlan MAC is
a secondary filter. Temporarily added `addresses: ["10.10.31.13/24"]` to
lab03's bond in `desired_fast_parent` (uncommitted, own subnet so replies
could not leak back via tagged fast30) and converged with
`CI= moon run fleet-cluster:network` (1 success, 3 no-change).
- ICMP and TCP to `10.10.31.13` from the tagged nas01 container: nothing,
  not even a TCP RST. Ambiguous on its own — could have been the IncusOS
  input firewall on a roleless interface.
- Disambiguated with hand-crafted ARP (AF_PACKET, answered by the kernel
  below nftables), unicast and broadcast in separate runs:
  - 3x unicast ARP request to `38:05:25:32:e1:3b` at 03:05:33 → **0 replies**
  - 3x broadcast ARP request at 03:05:37 → **3 replies in ~300us**

VERDICT: in Safe Mode the E810 delivers only broadcast/multicast. Unicast RX
is dropped for the primary MAC as well as macvlan secondaries, and every
tagged frame is dropped regardless of type. An untagged storage VLAN is
therefore NOT a viable stopgap — no switch- or VLAN-layer trick can carry
unicast into these NICs without the DDP package. The earlier ICMP/TCP
silence was the unicast drop, not the host firewall.

Correction to the 18:05 entry: the `/os/1.0/system/network` byte counters are
coarse/cached and sometimes report +0 while tcpdump proves frames arrived.
Treat container-side captures and switch-side counters as the ground truth;
the 18:05 conclusion still holds because it rests on those.

Revert, all verified:
- `operations.py` restored via `git checkout`; network deploy reconverged
  lab03 (1 success, 3 no-change); bond back to no addresses, fast30 `.13`.
- Switch: VLAN 30 tagged back to ports 1-7 with an empty untagged list;
  ports 5/6 back to `pvid=1`, `admit-only-vlan-tagged`,
  `ingress-filtering=true` — matches `bridge.tf` exactly (the declaration
  sets no pvid, so RouterOS default 1 is correct).
- All six test containers deleted. Baseline reconfirmed after revert:
  lab03→nas01 still delivers (nas01 fast rx 5.18MB → 5.52MB), nas01→lab03
  still 100% loss.
- `tofu plan` could NOT be run: the `lab-admin` AWS SSO token is expired, so
  the S3 backend is unreachable. Verified live state against `bridge.tf` by
  hand instead. Worth a real plan run after the next `aws sso login`.

Remaining options, in order of cost: wait for the stable release carrying
#1306 (cheapest, nothing else to do); or build a local IncusOS image with
incusos-builder including the merged fix and reinstall the three labs (works
today, but a three-node reinstall for a fix that ships on its own).
