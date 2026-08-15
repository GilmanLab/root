---
title: Hardware
description: Core network devices and their assigned roles.
---

# Hardware

## Core devices

| Component | Platform | Role |
| --- | --- | --- |
| Lab gateway | Minisforum VP6630 running VyOS | Routes lab networks, enforces firewall policy, and performs source NAT |
| Core switch | MikroTik `CRS309-1G-8S+IN` | Carries lab VLANs and connects lab devices at Layer 2 |
| Management/OOB switch | TRENDnet `TEG-3102WS` | Connects both non-SFP NICs from each MS-02 for management/OOB traffic |

## External dependency

| Component | Platform | Role |
| --- | --- | --- |
| Home router | MikroTik CCR2004 | Routes the home network, provides internet access, and terminates the upstream side of the routed lab transit |

The [physical connection map](physical-connections.md) records every installed
cable and its endpoint ports. The
[Lab v2 core network design](../../designs/drafts/lab-v2-core-network.md) defines
the logical topology and device boundaries.
