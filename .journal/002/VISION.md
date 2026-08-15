# GilmanLab v2 — Vision & Context

Working document. Purpose: give any agent enough context to work on the lab
without re-interviewing Josh. Every statement is tagged by confidence:

- **[DECIDED]** — settled; agents may rely on it. ADRs/designs are canonical where linked.
- **[PROVISIONAL]** — current thinking; may change; check before building on it.
- **[OPEN]** — known hole; do not assume an answer.

Canonical docs live in the `docs/` sub-repo (MkDocs site). This file holds the
vision, rationale, and everything not yet promoted into real docs.

---

## Purpose of the lab

**[OPEN]** Not yet articulated. What are the 2–3 real jobs this lab must do?

## Device naming

**[DECIDED]** Approved by Josh 2026-08-14; shipped in PR #8. Canonical
registry: `docs/docs/reference/naming.md`.

Rules:

- Every commissioned device gets exactly one canonical name. That name is the
  device's system identity (hostname / RouterOS identity / web-UI system name),
  its physical chassis label, and the only identifier used in docs and configs.
- Names are lowercase, DNS-safe labels (`a-z`, `0-9`, `-`), role-based, with a
  zero-padded two-digit ordinal.
- Uncommissioned hardware (shelf spares) has no name; the inventory refers to
  it by model. Names are assigned at commissioning.
- Repurposing a device means renaming it. Fleet is ~10 devices; the registry
  makes that a mechanical sweep.

Registry:

| Name | Device | Role |
| --- | --- | --- |
| `gw01` | Protectli VP6630 (VyOS) | Lab gateway |
| `rtr01` | MikroTik CRS309 #1 | Home router / internet edge |
| `sw-core01` | MikroTik CRS309 #2 | Core L2 switch |
| `sw-mgmt01` | TRENDnet TEG-3102WS | Management/OOB switch |
| `lab01`–`lab03` | Minisforum MS-02 Ultra x3 | Compute nodes |
| `nas01` | Minisforum N5 Pro | NAS |
| `pikvm01` | PiKVM V4 Plus | KVM-over-IP |
| `kvm01` | TESmart 8x1 HDMI KVM | Console switch |
| `ups01` | APC Smart-UPS SMT1000 | UPS |
| — | Minisforum UM760 | Shelf spare, unnamed until commissioned |

All other docs (inventory, cabling map, designs) reference devices by
canonical name. Setting the identity on each physical device (hostnames,
RouterOS identity, chassis labels) is a pending implementation task.

## Hardware (summary — canonical: docs/reference/hardware-inventory.md)

| Device | Qty | Role | Status |
| --- | --- | --- | --- |
| Protectli VP6630 (2x SFP+, 4x 2.5GbE) | 1 | Lab gateway, VyOS | [DECIDED] ADR-0001 |
| MikroTik CRS309-1G-8S+IN | 1 | Core L2 switch (lab VLANs) | [DECIDED] ADR-0001 |
| MikroTik CRS309-1G-8S+IN | 1 | Home router / internet edge | [DECIDED] per design draft |
| TRENDnet TEG-3102WS (8x 2.5G + 2x SFP+) | 1 | Management/OOB switch for MS-02s | [DECIDED] ADR-0001 |
| Minisforum MS-02 Ultra (Ultra 9 285HX, 64GB, 2TB+128GB NVMe, 2x 25G SFP+, 2x 2.5G, vPro/AMT) | 3 | Compute nodes LAB01–LAB03 | role [OPEN] — platform undecided |
| Minisforum N5 Pro NAS (Ryzen AI 9 HX PRO 370, 32GB, 2x 1TB NVMe + 128GB OS, 10GbE+5GbE) | 1 | NAS | role/scope [OPEN] |
| Minisforum UM760 (Ryzen 7, 32GB, 1x 2.5GbE) | 1 | Shelf spare — deliberately uncommissioned | [DECIDED] (for now) |
| PiKVM V4 Plus + TESmart 8x1 HDMI KVM | 1+1 | OOB console access | wiring [OPEN] |
| APC Smart-UPS SMT1000 (700W) | 1 | Power | mgmt card present, not hooked up (TODO); shutdown story [OPEN] |

## Networking (canonical: ADR-0001 + designs/drafts/lab-v2-core-network.md)

- **[DECIDED]** VyOS owns all L3: lab gateways, firewall, source NAT for internet
  egress. Switches are pure L2. Home→lab routed without NAT.
- **[DECIDED]** Physical topology per docs/reference/networking/physical-connections.md:
  each MS-02 has 2x SFP+ to core switch and 2x 2.5G to TEG-3102WS (mgmt/OOB).
  NAS 10G to core switch, NAS 5G to TEG-3102WS port 8. TEG uplinks to VP6630.
- **[PROVISIONAL]** Address/VLAN allocation, DHCP/DNS/NTP ownership explicitly
  out of scope of current docs — nothing decided yet.
- Note: MS-02 SFP+ ports are 25G-capable but CRS309 is 10G — links run at 10G.
  Expected, not a fault.

## Compute platform

**[OPEN]** Nothing documented. What runs on the MS-02s (hypervisor? Kubernetes?
bare metal?), and what the NAS serves and to whom.

## Known inconsistencies / holes (running list)

Resolved:

1. ~~UM760 role~~ — resolved: deliberately uncommissioned shelf spare.
2. ~~NAS 5GbE port~~ — resolved: connected to `sw-mgmt01` port 8; recorded as
   `PHY-019` in the cabling map (PR #8).

Open:

3. OOB/recovery story needs a real design: KVM video/USB wiring (which hosts
   feed the TESmart, where PiKVM connects), role of MS-02 vPro/AMT vs. KVM,
   recovery paths for VyOS and the switches.
4. Upstream of the home router (WAN handoff, modem/ONT) — undocumented,
   deliberately deprioritized for now.
5. UPS management card exists but is not hooked up (TODO). Monitoring and
   shutdown coordination undefined. 700W budget vs. full-load draw unverified.
6. VP6630 Port 1 unconnected — reserved for anything?
7. ~~Canonical device naming~~ — resolved: registry merged in PR #8. Remaining:
   apply names to device identities and chassis labels.

## Decisions log (pointers)

- ADR-0001: VyOS = L3, dedicated switches = L2 (accepted 2026-08-14).
