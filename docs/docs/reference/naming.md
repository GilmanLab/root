---
title: Device Naming
description: Canonical device names and the rules for assigning them.
---

# Device Naming

Every commissioned device has exactly one canonical name. The canonical name
is:

- the device's configured system identity (hostname, RouterOS identity, or
  web-UI system name),
- the physical label on the chassis, and
- the only device identifier used in documentation and configuration.

## Rules

- Names are lowercase DNS-safe labels: `a-z`, `0-9`, and `-`.
- Names are role-based with a zero-padded two-digit ordinal, for example
  `gw01`.
- Uncommissioned hardware has no name. The
  [hardware inventory](hardware-inventory.md) refers to it by model. A name is
  assigned when the device is commissioned.
- Repurposing a device renames it. Update this registry, the device's system
  identity, its chassis label, and every document that references the old
  name in the same unit of work.

## Registry

| Name | Device | Role |
| --- | --- | --- |
| `gw01` | Protectli VP6630 | Lab gateway running VyOS |
| `rtr01` | MikroTik CRS309-1G-8S+IN (unit 1) | Home router and internet edge |
| `sw-core01` | MikroTik CRS309-1G-8S+IN (unit 2) | Core Layer 2 switch |
| `sw-mgmt01` | TRENDnet TEG-3102WS | Management/OOB switch |
| `lab01` | Minisforum MS-02 Ultra (unit 1) | Compute node |
| `lab02` | Minisforum MS-02 Ultra (unit 2) | Compute node |
| `lab03` | Minisforum MS-02 Ultra (unit 3) | Compute node |
| `nas01` | Minisforum N5 Pro | NAS |
| `pikvm01` | PiKVM V4 Plus | KVM-over-IP console |
| `kvm01` | TESmart HKS801-EB23 8x1 KVM | Console switch |
| `ups01` | APC Smart-UPS SMT1000 | UPS |

## Unnamed hardware

| Device | Status |
| --- | --- |
| Minisforum UM760 | Shelf spare; named at commissioning |

Models and physical specifications live in the
[hardware inventory](hardware-inventory.md).
