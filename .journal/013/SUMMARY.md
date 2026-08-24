---
id: 013
title: Retest T48 after the 10G DAC swap
date: 2026-08-23
status: complete
repos_touched: []
related_sessions: [008, 009, 010]
---

## Goal

Recover the prior-session detail on the 25G DAC failures between the three
MS-02 lab nodes and `sw-core01`, then — after Josh replaced all six 25G DACs
with 10G DACs — establish the current state of T48 and test whether an
untagged storage VLAN would work as a stopgap until the upstream IncusOS ice
firmware fix ships.

## Outcome

Goal met; the underlying blocker is not fixed and cannot be worked around.

The DAC swap closed the FEC leg of T48 for good: all six lab links now run as
`SFP-H10GB-CU3M` at 10G with `Requested FEC: NONE, Negotiated FEC: NONE`,
where they previously requested RS-FEC and got NONE. The VLAN 30 datapath is
still dead switch→lab, so the DACs were necessary but not sufficient.

The remaining fault is exactly the missing ice DDP package, and this session
characterized it precisely: in Safe Mode the E810-XXV delivers only
broadcast/multicast, drops all unicast — the NIC's own primary MAC as well as
macvlan secondaries — and drops every VLAN-tagged frame regardless of type.
That rules out the untagged-VLAN-30 stopgap: no switch- or VLAN-layer change
can carry unicast into these NICs without the firmware. Decision: wait for
the stable release carrying lxc/incus-os#1306.

No repository changes were merged. Every experimental change (one fleet
desired-state edit, switch VLAN/PVID changes on lab03's two ports) was
deliberately reverted and verified, and all six test containers were deleted.

## Key Decisions

- Test the stopgap switch-side first, translating tagged↔untagged in the
  bridge, rather than reconfiguring hosts -> proved unicast RX was broken
  with zero host-config risk; only phase two needed a host address.
- Run the phase-two host change through `fleet-cluster:network` with an
  uncommitted `desired_fast_parent` edit, then revert by `git checkout` plus a
  reconverge -> honors the "all cluster config flows through the pyinfra
  project" mandate and makes the revert a one-command no-op instead of a
  hand-unwound ad-hoc PUT.
- Put the phase-two test address in `10.10.31.0/24`, not in VLAN 30's own
  subnet -> lab03 would otherwise have had two interfaces in
  `10.10.30.0/24`, and replies could have egressed via the tagged `fast30`,
  making a negative result meaningless.
- Settle the "is it the NIC or the IncusOS input firewall?" question with
  hand-crafted AF_PACKET ARP instead of adding interface roles -> ARP is
  answered by the kernel below nftables, so unicast-vs-broadcast ARP isolates
  the NIC with no further config churn.
- Accept live-state-vs-HCL verification for the switch revert instead of a
  `tofu plan` -> the `lab-admin` AWS SSO token is expired, so the S3 backend
  is unreachable; a real plan run is queued as an open thread rather than
  faking the check.
- Wait for the upstream release rather than building a local IncusOS image
  with the merged fix -> Josh's call; a three-node reinstall is not worth it
  for a fix that ships on its own.

## Changes

None landed. No PRs, no commits outside the journal.

Transient, all reverted and verified:

- `fleet/cluster/src/fleet_cluster/operations.py` - temporary
  `addresses: ["10.10.31.13/24"]` on lab03's bond in `desired_fast_parent`;
  reverted, `fleet-cluster:network` reconverged lab03 back to baseline.
- Live `sw-core01` - VLAN 30 untagged + `pvid=30` + `frame-types=admit-all`
  on `sfp-sfpplus5/6`; restored to tagged ports 1-7, empty untagged list,
  `pvid=1`, `admit-only-vlan-tagged`, `ingress-filtering=true`, matching
  `bridge.tf`.
- Six Alpine test containers (`t30-*`, `u30-*`, `v-*`) on pool `data`, all
  deleted.

## Open Threads

- **T48 unchanged as a blocker**, but its cause is now singular: waiting on
  the IncusOS stable release carrying lxc/incus-os#1306 (merged
  2026-08-22T05:04Z, `de271730`). Newest published build is still
  `202608201218` at `https://images.linuxcontainers.org/os/`, which is what
  all four nodes run. `auto_reboot: false`, so the update needs a manual
  reboot. Retest: cross-node macvlan pings on `fast30`, then
  `CI= moon run fleet-cluster:storage|network` reruns.
- Run `just plan` in `networking/routeros/sw-core01` after the next
  `aws sso login` to confirm the switch is byte-clean against state; live
  state was hand-verified against `bridge.tf` this session.
- The `svc-tofu` RouterOS password transited this transcript again (a
  `curl -v` Basic header). Rotation was already an open thread from 008.
- Fallback if VLAN 30 becomes urgent before upstream ships: build an image
  with `incusos-builder` including the merged fix and reinstall the three
  labs. Explicitly deferred.
- T44 (Operations Center spike), T45 (PiKVM creds), T46 (secrets checkout
  path), T47 (meshcommander) untouched.

## Lessons

- ice Safe Mode is far more destructive than "no advanced offloads": with no
  DDP the E810 passes broadcast/multicast only. Unicast to the primary MAC is
  dropped, so this is not a macvlan or secondary-MAC-filter problem, and
  `promisc on` does not rescue it.
- IncusOS `/os/1.0/system/network` byte counters are coarse or cached: they
  reported `+0` while tcpdump inside a container proved frames arrived. Use
  container-side captures plus switch-side counters as ground truth for
  datapath work.
- Unicast-vs-broadcast ARP crafted over AF_PACKET is a clean way to separate
  a NIC/driver RX fault from a host firewall policy, because the kernel
  answers ARP below nftables. Send the two variants in separate, spaced runs;
  interleaved bursts make the replies impossible to attribute.
- `incus launch -d <dev>` only overrides devices that already exist in a
  profile. Adding a new NIC needs `incus init` + `incus config device add` +
  `incus start`.
- Alpine's busybox `ping` has no `-b`, and busybox `ip` has no `-br`. A
  backgrounded `incus exec ... tcpdump &` can die silently; use
  `nohup ... &` inside the container and read the file back.

## References

- `.journal/013/NOTES.md` (full diagnostic arc, both phases)
- `.journal/010/SUMMARY.md` (original T48 diagnosis), `.journal/010/NOTES.md`
- `.journal/VISION.md` (T48)
- [lxc/incus-os#1305](https://github.com/lxc/incus-os/issues/1305) /
  [#1306](https://github.com/lxc/incus-os/pull/1306) ice DDP firmware
- `docs/docs/reference/networking/physical-connections.md`,
  `docs/docs/runbooks/sw-core01-configuration.md`
