---
title: Lab v2 core network
status: draft
authors:
  - GilmanLab
created: 2026-08-14
updated: 2026-08-14
related-decisions:
  - ADR-0001
---

# Lab v2 core network

## Summary

The core network uses a Minisforum VP6630 running VyOS for Layer 3 routing,
firewall policy, and NAT. A MikroTik CRS309-1G-8S+IN handles core Layer 2
switching and VLAN transport. A TRENDnet TEG-3102WS connects both non-SFP NICs
from each MS-02 to the VP6630 for management/OOB traffic. A second MikroTik
CRS309-1G-8S+IN acts as the home router and connects the lab to the home
network and the internet.

This design defines device responsibilities, logical topology, configuration
requirements, failure boundaries, and verification criteria. Address
allocation, VLAN allocation, physical port assignment, and network-service
ownership are outside this document.

## Goals

- Keep routing and traffic policy on VyOS.
- Keep core VLAN transport and physical switching on the core CRS309-1G-8S+IN.
- Carry MS-02 management/OOB traffic through the TEG-3102WS.
- Route home-to-lab traffic without source NAT.
- Apply source NAT to lab-to-internet traffic on VyOS.
- Store network-device configuration in version control.
- Validate behavior before saving a deployed configuration.
- Preserve a recovery path that does not depend on the primary network path.

## Non-goals

- Address and VLAN allocation
- Physical port and cable assignment
- DHCP, DNS, or time-service ownership
- Compute-platform network configuration
- Workload network overlays
- Application ingress or service advertisement
- Application DNS records
- Service-to-service traffic policy
- Storage protocol design

## Logical Topology

```mermaid
flowchart LR
    HOME[Home network] --> RTR[Home router CRS309-1G-8S+IN]
    RTR -->|Routed transit| VYOS[VP6630 running VyOS]
    VYOS -->|802.1Q trunk| CRS[Core CRS309-1G-8S+IN]
    CRS --> SEGMENTS[Lab network segments]
    VYOS -->|Management/OOB uplink| TEG[TEG-3102WS]
    TEG -->|Two non-SFP NICs per node| MS02[MS-02 nodes]
```

The home router routes traffic between the home network and the VyOS transit
interface. VyOS routes lab prefixes, applies firewall policy, and performs
source NAT for internet egress. The core CRS309-1G-8S+IN carries lab VLANs between
VyOS and connected lab devices. The TEG-3102WS connects directly to the VP6630
and carries management/OOB traffic for both non-SFP NICs on each MS-02.
The [physical connection map](../../reference/networking/physical-connections.md) is the
authoritative port-to-port cabling record.

## Device Responsibilities

| Device | Responsibilities |
| --- | --- |
| MikroTik CRS309-1G-8S+IN (home router) | Home-network routing, internet access, and the upstream side of the routed lab transit |
| Minisforum VP6630 running VyOS | Lab gateways, route selection, firewall policy, source NAT, the downstream side of the routed transit, and the management/OOB gateway |
| MikroTik CRS309-1G-8S+IN (core switch) | Core VLAN transport, access ports, trunks, and physical link aggregation |
| TRENDnet TEG-3102WS | Layer 2 management/OOB connectivity for both non-SFP NICs on each MS-02 and a direct uplink to the VP6630 |

[ADR-0001](../../decisions/0001-use-vyos-for-layer-3-and-switches-for-layer-2.md)
defines the Layer 2 and Layer 3 boundary.

## Routing and NAT

The routing design has these invariants:

- The home router has routes for lab prefixes through the VyOS transit address.
- VyOS uses the home router's transit address as its default route.
- VyOS owns the gateway address for every routed lab segment.
- The core CRS309-1G-8S+IN and TEG-3102WS do not route between lab segments.
- Home-to-lab traffic retains its original source address.
- VyOS applies source NAT to lab-to-internet traffic.
- Firewall rules distinguish new connections from established reply traffic.

## Traffic Policy

VyOS enforces policy for:

- Home network to lab segments
- Lab segments to the home network
- Lab segments to the internet
- Traffic between routed lab segments
- Traffic addressed to VyOS
- Management/OOB traffic through the TEG-3102WS
- Management traffic addressed to network devices

Each firewall rule identifies the source, destination, protocol, destination
port, connection direction, and owner. Rules permit required flows explicitly.
Stateful rules permit established reply traffic without permitting a new flow in
the reverse direction.

## Configuration Requirements

VyOS and both switches each have one version-controlled configuration source.
The deployment process:

1. Renders the effective configuration.
2. Validates syntax and policy before deployment.
3. Shows the effective change for operator review.
4. Applies the change without saving it as the startup configuration.
5. Verifies required connectivity and policy behavior.
6. Saves the configuration only after verification succeeds.
7. Restores the previous configuration when verification fails.

Drift detection compares each running configuration with its repository source.

## Management and Recovery

Firewall policy limits routine management access to approved source networks.
The TEG-3102WS carries management/OOB traffic from both non-SFP NICs on each
MS-02 directly to the VP6630.

Each network device has a recovery path that remains available when its
production configuration or primary network link fails. Recovery credentials do
not reside in device configuration committed to the repository.

## Failure Boundaries

| Failure | Effect |
| --- | --- |
| Home router failure | The lab loses home-network and internet connectivity. Internal lab switching and routing remain available. |
| VP6630 or VyOS failure | Routed lab segments lose their gateways, inter-segment routing, policy enforcement, management/OOB gateway, and internet egress. |
| Core switch failure | Devices connected through the core switch lose Layer 2 connectivity. |
| TEG-3102WS or its VP6630 uplink failure | Both non-SFP NICs on each MS-02 lose management/OOB connectivity. |
| Routed transit failure | Home-to-lab and lab-to-internet traffic stop. Internal lab traffic remains available within its unaffected Layer 2 and Layer 3 paths. |
| VyOS-to-core-switch trunk failure | VLANs carried by the trunk lose their VyOS gateways. |
| Invalid configuration | Deployment verification fails and the previous configuration is restored. |

## Verification

A deployment is valid when the observed behavior matches these checks:

- Every connected interface reports the assigned link state and speed.
- Each VLAN is present only on its assigned access ports and trunks.
- A client in each routed segment reaches its VyOS gateway.
- The home router and VyOS route tables contain the required transit and lab routes.
- Home-to-lab traffic retains its home-network source address.
- Lab-to-internet traffic uses the VyOS source-NAT address.
- Each permitted firewall flow succeeds.
- Each denied firewall flow fails.
- Established reply traffic succeeds without enabling a new reverse flow.
- Both non-SFP NICs on each MS-02 connect through the TEG-3102WS.
- MS-02 management/OOB traffic reaches the VP6630 through the TEG-3102WS
  uplink.
- Management access succeeds only from approved source networks.
- A failed deployment restores the previous configuration.
