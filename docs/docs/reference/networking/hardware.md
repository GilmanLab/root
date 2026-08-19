---
title: Hardware
description: Core network devices and their assigned roles.
---

# Hardware

Device names are canonical per the [naming registry](../naming.md).

## Core devices

| Device | Platform | Role |
| --- | --- | --- |
| `gw01` | Protectli VP6630 running VyOS | Routes lab networks, enforces firewall policy, and performs source NAT |
| `sw-core01` | MikroTik `CRS309-1G-8S+IN` | Carries lab VLANs and connects lab devices at Layer 2 |
| `sw-mgmt01` | TRENDnet `TEG-3102WS` | Connects both non-SFP NICs from each MS-02 for management/OOB traffic |

## External dependency

| Device | Platform | Role |
| --- | --- | --- |
| `rtr01` | MikroTik `CRS309-1G-8S+IN` | Routes the home network, provides internet access, and terminates the upstream side of the routed lab transit |

Models and physical specifications live in the
[hardware inventory](../hardware-inventory.md). The
[physical connection map](physical-connections.md) records every installed
cable and its endpoint ports. The
[Lab v2 core network design](../../designs/lab-v2-core-network.md) defines
the logical topology and device boundaries.
