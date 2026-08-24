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
