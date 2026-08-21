---
title: Network Address and VLAN Plan
description: Canonical routed prefixes, VLANs, DHCP allocations, and port roles.
---

# Network Address and VLAN Plan

This document is the canonical source for lab prefixes, VLANs, gateway
interface mapping, DHCP allocations, and logical switch port roles. The
[physical connection map](physical-connections.md) remains authoritative for
installed cables.

Deploy changes to the gateway with the
[VyOS gateway deployment runbook](../../runbooks/vyos-gateway-deployment.md).
The runbook identifies the repository source and operator commands; this page
remains the source for network values.

## Routed prefixes

| Network | Prefix | Gateway | Purpose |
| --- | --- | --- | --- |
| Router transit | `10.0.0.0/30` | `rtr01` `10.0.0.1`; `gw01` `10.0.0.2` | Routed link between the home router and lab gateway |
| Lab aggregate | `10.10.0.0/16` | More-specific VLAN gateways on `gw01` | Route advertised to `rtr01` and Tailscale |
| Home | `192.168.1.0/24` | `rtr01` | Home network routed to the lab without source NAT |
| Home | `192.168.2.0/24` | `rtr01` | Additional home network advertised through Tailscale |

`gw01` uses `10.0.0.1` as its default route. `rtr01` routes `10.10.0.0/16`
through `10.0.0.2`. `gw01` applies source NAT only when lab traffic exits
toward the internet. Home-to-lab and inter-VLAN traffic retain their source
addresses.

## VLANs

| VLAN | Name | Prefix | Gateway | Use |
| --- | --- | --- | --- | --- |
| `10` | Management | `10.10.10.0/24` | `10.10.10.1` | IncusOS management, network-device management, and `nas01` management |
| `40` | Sandbox/workload | `10.10.40.0/24` | `10.10.40.1` | `sandbox01` and future explicitly attached workload endpoints |
| `70` | OOB | `10.10.70.0/24` | `10.10.70.1` | MS-02 AMT, `pikvm01`, `kvm01`, and management-switch administration |

VLAN 20 and `10.10.20.0/24` are retired. The lab does not retain a PXE or
Tinkerbell provisioning network.

The management and OOB VLANs remain separate. The sandbox/workload VLAN cannot
initiate connections to management or OOB endpoints. Firewall policy permits
required administration flows explicitly and permits established replies.

## Address allocations

### Infrastructure and services

| Endpoint | Address | Allocation |
| --- | --- | --- |
| `gw01` management gateway | `10.10.10.1` | Interface address |
| `sw-core01` management | `10.10.10.2` | Interface address |
| `gw01` sandbox/workload gateway | `10.10.40.1` | Interface address |
| `gw01` OOB gateway | `10.10.70.1` | Interface address |
| `sw-mgmt01` management | `10.10.70.2` | Interface address |
| `gw01` `glab.lol` mirror | `10.10.10.54` | Local service address |

### Hosts

| Device | Management | OOB | Notes |
| --- | --- | --- | --- |
| `lab01` | `10.10.10.11` | `10.10.70.11` | 10GbE RJ45 management; 2.5GbE RJ45 AMT |
| `lab02` | `10.10.10.12` | `10.10.70.12` | 10GbE RJ45 management; 2.5GbE RJ45 AMT |
| `lab03` | `10.10.10.13` | `10.10.70.13` | 10GbE RJ45 management; 2.5GbE RJ45 AMT |
| `nas01` | `10.10.10.14` | — | 5GbE RJ45 management link through `sw-mgmt01` |
| `sandbox01` | `10.10.40.10` | — | Direct untagged sandbox/workload attachment to `gw01` |
| `pikvm01` | — | `10.10.70.20` | Direct untagged attachment to `gw01` |
| `kvm01` | — | `10.10.70.21` | Direct untagged attachment to `gw01` |

`gw01` supplies DHCP on every client VLAN. Named hosts use DHCP reservations.
Gateway and managed-switch interface addresses and the local DNS mirror address
are static. Dynamic clients use `.200` through `.250` within each client VLAN.
Reservations use each endpoint's permanent hardware MAC address as recorded in
the version-controlled gateway configuration.

IncusOS seed data enables DHCP on the 10GbE management interface. The 2.5GbE
vPro interface receives its OOB reservation independently from AMT firmware.

## Gateway interface mapping

| `gw01` chassis port | VyOS interface | Mode | Network |
| --- | --- | --- | --- |
| `SFP+ 1` | `eth0` | Routed | Transit `10.0.0.2/30` to `rtr01` |
| `SFP+ 2` | `eth1` | 802.1Q trunk | VLANs 10 and 40 to `sw-core01` |
| `Port 1` | `eth3` | 802.1Q trunk | VLANs 10 and 70 to `sw-mgmt01` |
| `Port 2` | `eth2` | Untagged access | VLAN 40 to `sandbox01` |
| `Port 3` | `eth4` | Untagged access | VLAN 70 to `pikvm01` |
| `Port 4` | `eth5` | Untagged access | VLAN 70 to `kvm01` |

The non-sequential `eth2` and `eth3` mapping follows the installed cabling and
live link state observed on the VP6630.

## Switch port roles

### `sw-mgmt01`

| Port | Mode | VLAN | Endpoint |
| --- | --- | --- | --- |
| `1` | Trunk | 10, 70 | `gw01` |
| `2` | Access | 10 | `lab01` 10GbE RJ45 management |
| `3` | Access | 70 | `lab01` 2.5GbE RJ45 AMT |
| `4` | Access | 10 | `lab02` 10GbE RJ45 management |
| `5` | Access | 70 | `lab02` 2.5GbE RJ45 AMT |
| `6` | Access | 10 | `lab03` 10GbE RJ45 management |
| `7` | Access | 70 | `lab03` 2.5GbE RJ45 AMT |
| `8` | Access | 10 | `nas01` 5GbE RJ45 management |

`sw-mgmt01` has 2.5GBASE-T access ports. The MS-02 10GbE management NICs and
the `nas01` 5GbE NIC therefore negotiate no faster than 2.5Gbps on this switch.

### `sw-core01`

Port 8 is the 802.1Q trunk to `gw01` and carries VLANs 10 and 40. VLAN 10
provides the switch management path. Ports 1 through 6 connect the two SFP+
interfaces from each MS-02, and port 7 connects the `nas01` 10GbE interface.
Those compute-facing links receive instance, cluster, or storage VLAN
membership only after the compute-network design assigns their roles; they are
not required for initial IncusOS management boot.

## DHCP and DNS ownership

`gw01` is available before managed hosts boot and owns cold-start DHCP and DNS
forwarding. Clients use their VLAN gateway address as the DNS resolver.

The CoreDNS service on `gw01` answers `glab.lol` from a local mirror of the
private Route 53 zone and forwards other queries to the configured recursive
resolvers. `gw01` does not run PowerDNS and does not serve `lab.gilman.io`.

## Routing protocols

The initial core network uses connected and static routes only. It does not
configure BGP. A later design may add BGP when a concrete workload-advertisement
or dynamic-routing requirement exists.
