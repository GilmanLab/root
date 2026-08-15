---
title: Physical Connections
description: Authoritative port-to-port map of the installed network cabling.
---

# Physical Connections

Each row records one installed cable. Port names match the labels on the device
chassis. `Unlabeled Ethernet port` identifies a physical Ethernet port that has
no printed label. Two MikroTik CRS309-1G-8S+IN units are installed; rows
qualify them by role as `(home router)` and `(core switch)`.

## Connected ports

| Connection | Device A | Port A | Device B | Port B |
| --- | --- | --- | --- | --- |
| `PHY-001` | MikroTik CRS309-1G-8S+IN (home router) | `SFP+ 1` | Minisforum VP6630 | `SFP+ 1` |
| `PHY-002` | Minisforum VP6630 | `SFP+ 2` | MikroTik CRS309-1G-8S+IN (core switch) | `Port 8` |
| `PHY-003` | Minisforum VP6630 | `Port 2` | TRENDnet TEG-3102WS | `Port 1` |
| `PHY-004` | Minisforum VP6630 | `Port 3` | PiKVM | `Unlabeled Ethernet port` |
| `PHY-005` | Minisforum VP6630 | `Port 4` | TESmart 8x1 KVM | `Unlabeled Ethernet port` |
| `PHY-006` | TRENDnet TEG-3102WS | `Port 2` | LAB01 | `Top Port` |
| `PHY-007` | TRENDnet TEG-3102WS | `Port 3` | LAB01 | `Bottom Port` |
| `PHY-008` | TRENDnet TEG-3102WS | `Port 4` | LAB02 | `Top Port` |
| `PHY-009` | TRENDnet TEG-3102WS | `Port 5` | LAB02 | `Bottom Port` |
| `PHY-010` | TRENDnet TEG-3102WS | `Port 6` | LAB03 | `Top Port` |
| `PHY-011` | TRENDnet TEG-3102WS | `Port 7` | LAB03 | `Bottom Port` |
| `PHY-012` | MikroTik CRS309-1G-8S+IN (core switch) | `Port 1` | LAB01 | `Right SFP 25G` |
| `PHY-013` | MikroTik CRS309-1G-8S+IN (core switch) | `Port 2` | LAB01 | `Left SFP 25G` |
| `PHY-014` | MikroTik CRS309-1G-8S+IN (core switch) | `Port 3` | LAB02 | `Right SFP 25G` |
| `PHY-015` | MikroTik CRS309-1G-8S+IN (core switch) | `Port 4` | LAB02 | `Left SFP 25G` |
| `PHY-016` | MikroTik CRS309-1G-8S+IN (core switch) | `Port 5` | LAB03 | `Right SFP 25G` |
| `PHY-017` | MikroTik CRS309-1G-8S+IN (core switch) | `Port 6` | LAB03 | `Left SFP 25G` |
| `PHY-018` | MikroTik CRS309-1G-8S+IN (core switch) | `Port 7` | NAS | `10GB Port` |

## Unconnected ports

Only ports explicitly identified as unconnected are listed.

| Device | Port |
| --- | --- |
| Minisforum VP6630 | `Port 1` |
| TRENDnet TEG-3102WS | `Port 8` |

IP addresses, VLANs, bonds, interface names, and link settings belong to the
network configuration rather than this physical map.
