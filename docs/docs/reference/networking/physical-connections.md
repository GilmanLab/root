---
title: Physical Connections
description: Authoritative port-to-port map of the installed network cabling.
---

# Physical Connections

Each row records one installed cable. Device names are canonical per the
[naming registry](../naming.md). Port names match the labels on the device
chassis. `Unlabeled Ethernet port` identifies a physical Ethernet port that has
no printed label.

## Connected ports

| Connection | Device A | Port A | Device B | Port B |
| --- | --- | --- | --- | --- |
| `PHY-001` | `rtr01` | `SFP+ 1` | `gw01` | `SFP+ 1` |
| `PHY-002` | `gw01` | `SFP+ 2` | `sw-core01` | `Port 8` |
| `PHY-003` | `gw01` | `Port 2` | `sw-mgmt01` | `Port 1` |
| `PHY-004` | `gw01` | `Port 3` | `pikvm01` | `Unlabeled Ethernet port` |
| `PHY-005` | `gw01` | `Port 4` | `kvm01` | `Unlabeled Ethernet port` |
| `PHY-006` | `sw-mgmt01` | `Port 2` | `lab01` | `Top Port` |
| `PHY-007` | `sw-mgmt01` | `Port 3` | `lab01` | `Bottom Port` |
| `PHY-008` | `sw-mgmt01` | `Port 4` | `lab02` | `Top Port` |
| `PHY-009` | `sw-mgmt01` | `Port 5` | `lab02` | `Bottom Port` |
| `PHY-010` | `sw-mgmt01` | `Port 6` | `lab03` | `Top Port` |
| `PHY-011` | `sw-mgmt01` | `Port 7` | `lab03` | `Bottom Port` |
| `PHY-012` | `sw-core01` | `Port 1` | `lab01` | `Right SFP 25G` |
| `PHY-013` | `sw-core01` | `Port 2` | `lab01` | `Left SFP 25G` |
| `PHY-014` | `sw-core01` | `Port 3` | `lab02` | `Right SFP 25G` |
| `PHY-015` | `sw-core01` | `Port 4` | `lab02` | `Left SFP 25G` |
| `PHY-016` | `sw-core01` | `Port 5` | `lab03` | `Right SFP 25G` |
| `PHY-017` | `sw-core01` | `Port 6` | `lab03` | `Left SFP 25G` |
| `PHY-018` | `sw-core01` | `Port 7` | `nas01` | `10GB Port` |
| `PHY-019` | `sw-mgmt01` | `Port 8` | `nas01` | `5GB Port` |

## Unconnected ports

Only ports explicitly identified as unconnected are listed.

| Device | Port |
| --- | --- |
| `gw01` | `Port 1` |

IP addresses, VLANs, bonds, interface names, and link settings belong to the
network configuration rather than this physical map.
