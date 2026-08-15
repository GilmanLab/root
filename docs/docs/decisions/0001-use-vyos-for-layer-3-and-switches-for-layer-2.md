---
status: accepted
date: 2026-08-14
---

# ADR-0001: Use VyOS for Layer 3 and Dedicated Switches for Layer 2

## Context and Problem Statement

The core network needs explicit ownership for switching, routing, and traffic
policy. The network uses a VyOS gateway, a MikroTik CRS309-1G-8S+IN core switch,
and a TRENDnet TEG-3102WS management/OOB switch. Which devices own each network
function?

## Decision Drivers

- Keep routed gateways and firewall policy on one device.
- Keep switch configuration focused on Layer 2 transport and physical links.
- Make the enforcement point for traffic between routed lab segments explicit.
- Carry MS-02 management/OOB traffic on its dedicated copper switch.
- Use the selected VyOS, MikroTik, and TRENDnet hardware.

## Considered Options

- Use VyOS for Layer 3 and dedicated switches for Layer 2.
- Use MikroTik for Layer 2 and Layer 3, with VyOS at the external edge.
- Use one flat Layer 2 lab network, with VyOS as its external gateway.

## Decision Outcome

Use VyOS for routed lab gateways, route selection, firewall policy, and NAT. Use
the MikroTik CRS309-1G-8S+IN for core Layer 2 switching and VLAN transport. Use
the TRENDnet TEG-3102WS for Layer 2 management/OOB connectivity from both
non-SFP NICs on each MS-02. The TEG-3102WS uplinks directly to the VP6630, which
provides the management/OOB gateway and firewall policy.

DHCP, DNS, and time-service ownership are outside the scope of this decision.

### Consequences

- Good, because routed traffic has one policy-enforcement point.
- Good, because each device has a distinct configuration boundary.
- Good, because the MS-02 management/OOB links use a dedicated physical switch.
- Bad, because traffic between routed lab segments depends on VyOS.
- Bad, because routed segments carried through the CRS309-1G-8S+IN depend on
  its trunk to VyOS.
- Bad, because MS-02 management/OOB access depends on the TEG-3102WS and its
  uplink to the VP6630.

### Confirmation

The implementation conforms to this decision when:

- VyOS owns the gateway address for each routed lab segment, including the
  management/OOB segment.
- VyOS contains the firewall and NAT policy for routed lab traffic.
- Neither switch routes traffic between lab segments.
- CRS309-1G-8S+IN configuration defines core VLAN membership, trunks, access
  ports, and physical link aggregation.
- TEG-3102WS configuration and cabling connect both non-SFP NICs from each MS-02
  to the VP6630 management/OOB gateway.

Management addresses on the switches do not violate this decision.

## Pros and Cons of the Options

### VyOS Layer 3 and Dedicated Layer 2 Switches

- Good, because routing and firewall policy use the same configuration
  boundary.
- Good, because the switches remain independent of higher-level traffic policy.
- Good, because core and management/OOB traffic use separate physical switches.
- Bad, because VyOS is on the forwarding path for all routed lab traffic.
- Bad, because each switch is a failure boundary for its connected links.

### MikroTik Layer 2 and Layer 3

- Good, because the core switch can route traffic without sending it through
  the VyOS trunk.
- Bad, because firewall and routing ownership would be split between devices.
- Bad, because the network would need policy coordination between MikroTik and
  VyOS.

### Flat Layer 2 Lab Network

- Good, because it requires fewer routed interfaces and policies.
- Bad, because it cannot enforce boundaries between lab network functions.
- Bad, because broadcasts and Layer 2 failures share one domain.

## More Information

See the [Lab v2 core network design](../designs/drafts/lab-v2-core-network.md)
and [hardware reference](../reference/networking/hardware.md).
