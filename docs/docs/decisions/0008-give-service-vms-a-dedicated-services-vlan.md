---
status: accepted
date: 2026-10-16
decision-makers:
  - Josh Gilman
---

# ADR-0008: Give Service VMs a Dedicated Services VLAN

## Context and Problem Statement

Long-lived service VMs (first: `media01`) need a routed LAN address reachable
from home and the tailnet. The instance VLAN 40 parent `fast40` is owned by
OVN as its physical uplink, and a raw macvlan on that parent stops OVS from
attaching it, breaking north-south traffic whenever that member is the OVN
gateway ([lxc/incus#3986](https://github.com/lxc/incus/issues/3986)). Where
should service VMs attach?

## Decision Drivers

- Must not interfere with the OVN sandbox fabric (ADR-0006).
- Keep internet-adjacent workloads off the management VLAN.
- Plain L2 attachment with no dependency on OVN central.

## Considered Options

- New routed services VLAN 50 carried only to the members that host service
  VMs.
- A dedicated OVN network with a network forward.
- Bridged NIC on the management VLAN 10, like `ovncentral01`.

## Decision Outcome

Chosen option: **services VLAN 50** (`10.10.50.0/24`, gateway `gw01`). It is
tagged on `sw-core01` port 8 (gw01 trunk) and the ports of members that host
service VMs (today `nas01`, port 7). IncusOS declares an address-less
`fast50` interface on those members, and service VMs attach with
`nictype=macvlan parent=fast50`. gw01 lets the VLAN reach the internet and
blocks new connections from it to management, OOB, sandbox, and home networks.
Management, home, and Tailscale clients can open connections into it.

### Consequences

- Good, because OVN keeps exclusive use of `fast40` on every member.
- Good, because a compromised service VM cannot open connections to the
  management plane or the home network.
- Bad, because a new VLAN touches gw01, sw-core01, and fleet, and every new
  service host member needs its switch port tagged.

### Confirmation

`incus network show nas01:fast40 --target <member>` lists only
`fast40-uplink` in `used_by`. The media root rejects `network_parent=fast40`.

## More Information

- [Network address and VLAN plan](../reference/networking/address-plan.md)
- [Deploy and operate the media stack](../runbooks/media-stack.md)
