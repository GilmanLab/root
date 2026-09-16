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
through `10.0.0.2`. `gw01` applies source NAT in exactly two cases: lab
traffic exiting toward the internet, and Tailscale clients
(`100.64.0.0/10`) entering the sandbox/workload VLAN. The sandbox
masquerade keeps replies from tailnet-member hosts such as `sandbox01`
symmetric through `gw01` instead of leaking into the host's own tailscale
peer routes. All other home-to-lab, Tailscale-to-lab, and inter-VLAN
traffic retains its source addresses.

## VLANs

| VLAN | Name | Prefix | Gateway | Use |
| --- | --- | --- | --- | --- |
| `10` | Management | `10.10.10.0/24` | `10.10.10.1` | IncusOS management, network-device management, and `nas01` management |
| `30` | Storage | `10.10.30.0/24` | None (not routed) | Incus node storage network on the compute-facing `sw-core01` links |
| `40` | Sandbox/workload | `10.10.40.0/24` | `10.10.40.1` | `sandbox01`, Incus instances attached over the cluster fast links, and other explicitly attached workload endpoints |
| `70` | OOB | `10.10.70.0/24` | `10.10.70.1` | MS-02 AMT, `pikvm01`, `kvm01`, and management-switch administration |

VLAN 20 and `10.10.20.0/24` are retired. The lab does not retain a PXE or
Tinkerbell provisioning network.

The management and OOB VLANs remain separate. The sandbox/workload VLAN cannot
initiate connections to management or OOB endpoints. Firewall policy permits
required administration flows explicitly and permits established replies.

The storage VLAN is Layer 2 only. It has no gateway interface, is not carried
on the `gw01` trunk, and is therefore unreachable from every routed network by
construction. Its addresses are static IncusOS runtime configuration converged
by the `GilmanLab/fleet` `cluster/` project and mirrored in each node's seed.

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
| `ovncentral01` OVN central | `10.10.10.15` | Static VM interface on `nas01`'s unmanaged `mgmt` bridge |
| `agentcompute01` MCP service | `10.10.10.16` | Static `/32` on a routed Incus NIC through `lab01`'s `_vmgmt` interface; host gateway `169.254.0.1` |

### Hosts

| Device | Management | Storage | OOB | Notes |
| --- | --- | --- | --- | --- |
| `lab01` | `10.10.10.11` | `10.10.30.11` | `10.10.70.11` | 10GbE RJ45 management; SFP+ LAG storage; 2.5GbE RJ45 AMT |
| `lab02` | `10.10.10.12` | `10.10.30.12` | `10.10.70.12` | 10GbE RJ45 management; SFP+ LAG storage; 2.5GbE RJ45 AMT |
| `lab03` | `10.10.10.13` | `10.10.30.13` | `10.10.70.13` | 10GbE RJ45 management; SFP+ LAG storage; 2.5GbE RJ45 AMT |
| `nas01` | `10.10.10.14` | `10.10.30.14` | — | 5GbE RJ45 management link through `sw-mgmt01`; 10GbE storage |
| `sandbox01` | `10.10.40.10` | — | — | Direct untagged sandbox/workload attachment to `gw01` |
| `pikvm01` | — | — | `10.10.70.20` | Direct untagged attachment to `gw01` |
| `kvm01` | — | — | `10.10.70.21` | Direct untagged attachment to `gw01` |

`gw01` supplies DHCP on every client VLAN. Dynamic clients use `.200` through
`.250` within each client VLAN. DHCP-served named hosts (`sandbox01`,
`pikvm01`, `kvm01`) use reservations keyed on each endpoint's permanent
hardware MAC address as recorded in the version-controlled gateway
configuration.

Infrastructure endpoints do not depend on DHCP: gateway and managed-switch
interface addresses and the local DNS mirror address are static interface
configuration; the OVN central address is static VM network configuration;
IncusOS node management addresses are static in each node's seed (bound to the
management NIC's hardware MAC in `GilmanLab/fleet`); storage-network addresses
are static IncusOS runtime configuration (converged by the fleet `cluster/`
project and mirrored in the seeds); and lab-node AMT addresses are static in
MEBx so out-of-band access survives a gateway outage. The AMT interfaces have
no DHCP reservations.

### OVN external addresses

Reserve `10.10.40.64` through `10.10.40.127` (64 addresses) for OVN
virtual-router external addresses and network forwards. The owner approved
this durable allocation on 2026-09-12, replacing the `.64`–`.79` spike
reservation. Fleet owns `ipv4.ovn.ranges` on the default-project physical
network `fast40-uplink`.

The allocation stays inside the physical uplink's existing
`10.10.40.0/24` gateway subnet; it is not a new routed subnet and requires no
new route or VLAN. Do not add this reservation to `ipv4.routes` on
`fast40-uplink`: Incus authorizes addresses from the uplink's configured
gateway subnet. The `.200`–`.250` DHCP pool and named endpoints remain
unchanged. Do not assign the reserved addresses to other endpoints.

Capacity accounting charges one external address for each NAT-enabled OVN
network and one for each distinct forward listen address. An isolated
`nat=false` network uses `network=none` and consumes no external address.
Guests use internal addresses, and additional ports sharing a listen address
do not consume another external address. Forwards are not available on
isolated networks.

| Sandbox topology | External addresses per sandbox | Eight concurrent sandboxes |
| --- | ---: | ---: |
| NAT-enabled `default` network and one forward listen address | 2 | 16 |
| NAT-enabled `default`, isolated `lan`, NAT-enabled `wan`, and one forward listen address | 3 | 24 |

The planning target is eight concurrent sandboxes for the single operator
and their agents. The representative three-network topology uses 24 of the
64 addresses and leaves 40 for additional NAT-enabled networks, distinct
forward addresses, and pending cleanup. These are address-budget
calculations, not measured scale limits.

An `Errored` NAT-enabled OVN network retains its external address until
deleted and counts against capacity. If central is unavailable, the reaper
leaves cleanup pending and retries deletion after central recovers; it does not
repair the network with service restarts. Revisit a dedicated VLAN only
when OVN needs more than this 64-address allocation.

Durable OVN central uses the `ovncentral01` allocation listed above. The VM is
pinned to `nas01` and attaches directly to its unmanaged VLAN 10 `mgmt`
bridge, so management boot and central do not depend on OVN. The standalone
northbound and southbound databases accept mutual TLS only on ports `6641`
and `6642`; chassis encapsulation uses the members' VLAN 30 addresses. The
qualification spike central on `sandbox01` has been removed. See the
[OVN central and certificate runbook](../../runbooks/ovn-central-and-certificates.md)
for deployment, renewal, and recovery procedures.

### Incus-local and service networks

These private prefixes are not routed lab VLANs. Do not advertise them through
`gw01` or Tailscale. `incusbr0` and `github-runners` are member-local NAT
bridges. `ac-svc-vlan40` is a managed OVN network whose uplink remains
`fast40-uplink`.

| Resource | Address or prefix | Ownership |
| --- | --- | --- |
| Existing `incusbr0` bridge | `10.158.84.0/24`, gateway `.1` | IncusOS |
| `github-runners` bridge | `10.158.85.0/24`, gateway `.1` | Fleet `cluster/` |
| Agentcompute service network `ac-svc-vlan40` | `10.158.86.0/24`, gateway `.1`; `agentcompute01` guest NIC `.2` | Fleet OpenTofu root `incus/agentcompute/` |
| Reserved controller VM `ghrunner01` on `nas01` | `10.158.84.50` | Fleet OpenTofu root `incus/incus-gh-runner/` |
| Reserved HTTP CONNECT forward | `10.10.10.14:3128` → `10.158.84.50:3128` | Same OpenTofu root, member-local to `nas01` |

Runner egress permits the management gateway's DNS service, the pinned Incus
API at `10.10.10.14:8443`, and the proxy port. The ACL also permits the exact
proxy destination after DNAT because network-forward translation precedes
the network ACL on the member hosting the forward. No other controller
port is exposed by that forward. See the
[private image runner runbook](../../runbooks/private-image-runners.md)
for deployment and cutover checks.

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
provides the switch management path. Ports 1 through 6 form three 802.3ad
LAGs, one per MS-02 SFP+ pair: `bond-lab01` (ports 1–2), `bond-lab02` (ports
3–4), and `bond-lab03` (ports 5–6). Port 7 connects the `nas01` 10GbE
interface. VLANs 30 and 40 are tagged on the three LAGs and port 7: VLAN 30
is the node storage network, and VLAN 40 carries Incus instance traffic so
workloads stay off the management plane. These links are not required for
IncusOS management boot. The host-side counterpart, converged by the
`GilmanLab/fleet` `cluster/` project, is the `vlan_tags` allow-list plus an
IncusOS-declared VLAN interface per carried VLAN (`fast30`, `fast40`).
Instances must attach to the IncusOS-owned interface (for example macvlan
with `parent=fast40`), never with an Incus-created `vlan=` sub-interface on
`fast`: the visible `fast` device is an IncusOS-internal VLAN-filtering
bridge, and only IncusOS-declared VLANs receive bridge self-port membership,
so other tagged sub-interfaces pass no traffic. Additional instance VLANs
join these links when their first consumer arrives.

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
