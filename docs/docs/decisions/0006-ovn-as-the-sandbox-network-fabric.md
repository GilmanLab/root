---
status: proposed
date: 2026-09-12
decision-makers:
  - Josh Gilman
---

# ADR-0006: OVN as the Sandbox Network Fabric

## Context and Problem Statement

Agentcompute needs disposable networks spanning Incus members, with NAT,
peering, ACLs, and operator-reachable forwards. Phase 2 bridges proved the
sandbox lifecycle but provide separate member-local L2 domains. Phase 3
qualified OVN after removing a raw macvlan fixture that prevented OVS from
claiming the provider parent. Which fabric should the durable service use?

## Decision Drivers

- Cross-member guest connectivity without a router instance for ordinary
  NAT-enabled and peered segments.
- Sandbox traffic cannot initiate connections to management or OOB.
- Fleet owns infrastructure; agents own only disposable sandbox resources.
- Management boot and OVN central must not depend on OVN itself.
- Native `nat=false`, `network=none` isolation must use the same durable
  control plane as NAT-enabled sandbox networks.
- Failed creates and expired resources must converge through explicit,
  retryable deletion rather than undocumented service repairs.

## Considered Options

- OVN with one independent central VM and the existing workload VLAN
- Member-local bridges only
- OVN with a dedicated provider VLAN
- A replicated OVN central cluster

## Decision Outcome

Proposed choice: **OVN with one independent central VM and the existing
workload VLAN**. The owner has approved the VLAN and address budget; this
record remains `proposed` until the owner accepts the fabric decision.

Fleet's `incus/ovn-central/` OpenTofu root owns `ovncentral01`, one VM pinned
to `nas01` and attached to its unmanaged VLAN 10 `mgmt` bridge rather than an
OVN network. The pinned `ovn-central` package version `26.03.0-2` supplies
northd and standalone NB/SB databases, without Raft. Per-component TLS gates
prevent either database from starting without the complete certificate trio.
Remote database connections use mutual TLS from a dedicated offline OVN
application CA, not the KMS root or the Incus cluster certificate. The CA uses
EC P-256, has a ten-year validity and no path-length constraint. Central and
each chassis have separate two-year leaves. Per-chassis keys allow one member's
identity to rotate without distributing the same private key to every node.
The TLS cutover occurred only after the cluster carried the CVE-2026-40243 fix.

The owner approved this application-scoped trust domain on 2026-09-12,
superseding the draft's requirement to use the ADR-0005 hierarchy. The
dedicated offline OVN CA is outside ADR-0005's KMS-root hierarchy; ADR-0005 is
not amended. Revisit the issuance model when Vault PKI exists and there is a
reason to migrate.

The CA key and every leaf key are escrowed under the `fleet` scope in
`GilmanLab/secrets`, following ADR-0003's alternative KMS/PGP recipients and
scoped encryption context. The CA key is used only in a controlled fleet
issuance ceremony and is never delivered to central or a chassis. Private leaf
material is delivered outside OpenTofu state and plaintext node seeds.

A chassis leaf rotates in one fleet deploy. A central-leaf renewal and a
complete CA plus all-five-leaf replacement use the fleet `central-tls`
delivery while all central components are stopped. The delivery validates and
installs changed TLS files without touching `/var/lib/ovn` or controlling
service lifecycle. A full trust-set replacement starts central with the new CA
before fleet updates the Incus client and four chassis identities, producing a
brief fail-closed mismatch without a dual-CA interval. TLS renewal does not
replace the VM. Deliberate VM replacement remains reserved for bootstrap or
package changes and has the empty-database consequences described in the
[OVN central and certificate runbook](../runbooks/ovn-central-and-certificates.md).
OpenTofu's public CA and central-certificate metadata must be updated in place
after rotation; the central private key is never an OpenTofu input.

Fleet's `cluster/` deployment owns chassis configuration on every member,
using VLAN 30 tunnel addresses and central's VLAN 10 endpoint. Supported
settings are mirrored in node seeds. The default-project physical uplink
`fast40-uplink` exclusively owns the IncusOS `fast40` provider parent. Before
convergence, fleet checks member-specific networks, profiles, and instance
NICs, including inherited and stopped-instance devices. A competing direct
parent attachment or physical-uplink NIC aborts deployment with a named
conflict; fleet never removes it silently.

The [address plan](../reference/networking/address-plan.md#ovn-external-addresses)
is authoritative for the approved external allocation and its eight-sandbox
budget. VLAN 40, DHCP allocations, and named endpoints stay in place. The
reservation is inside the uplink gateway subnet, not a routed subnet. Fleet
sets `ipv4.ovn.ranges` but does not add a redundant `ipv4.routes` allowlist;
the configured uplink gateway subnet already authorizes its addresses.
Reconsider a dedicated VLAN only if OVN needs more than the approved
64-address block.
The representative topology has NAT-enabled `default` and `wan` networks, an
isolated `lan`, and one distinct forward listen address. It consumes three
external addresses per sandbox. Eight sandboxes consume 24; the service's
`ac-svc-vlan40` network consumes one more, leaving 39 of the 64-address reservation.

New sandbox projects use project-owned OVN networks and managed-only NICs.
The default network has NAT. An additional NAT-enabled network consumes one
external address and has a direct path toward the lab and internet, subject to
ACL and gateway policy. An isolated `nat=false` network uses `network=none`,
consumes no external address, and has no direct path outside its sandbox. It
becomes reachable only through `net.peer` or a router instance attached to
another network. A `net.forward` request for an isolated network returns
`AgentError`.
Both the overlay control plane and the native isolation contract require
central. Without central, Incus cannot create the project-owned logical switch
whose `network=none` setting makes a `nat=false` network isolated. Replacing
central would therefore require replacing the selected OVN fabric, not only
the central VM.

The `default_network_kind=bridge` fallback keeps whole sandboxes on
member-local bridges; explicit bridge networks remain bare wires there. Incus
cannot expose default-project bridges to an OVN project's managed-only NICs,
so mixed OVN/bridge requests return `AgentError`, not a rewritten network kind
or an unmanaged NIC. Existing bridge sandboxes expire and are deleted, never
converted in place.

The server installs management/OOB baseline ACL denies that agent ACL calls
cannot remove. The current software contract also rejects every `allow` rule
unless `dst` is an explicit IP address or CIDR that does not overlap either
protected range. This applies to ingress and egress because Incus evaluates
native ingress fields from the opposite endpoint perspective. The restriction
remains conservative while native ACL interaction is qualified; this record
does not assume that a native priority relationship makes a broader allow
safe.

### Consequences

- OVN networks span members and provide logical routing, DHCP, DNS, ACLs, and
  peering through Incus rather than guest-specific configuration.
- NAT-enabled networks provide SNAT and may host forwards. Isolated
  `nat=false` networks provide neither an external allocation nor a direct lab
  or internet path; a peer or dual-NIC router must supply intentional
  reachability.
- One central VM is a single control-plane failure domain. Every OVN create,
  update, and delete requires central availability. Existing installed flows
  may continue during an outage; that does not permit mutations.
- An `Errored` NAT-enabled network keeps its external address until deletion.
  Capacity accounting includes failed NAT-enabled networks and pending
  teardown.
- During a central outage, the reaper leaves expired projects pending. After
  central recovers, a later scan continues dependency-ordered deletion:
  forwards and peers, NIC references, instances and snapshots, sandbox images,
  profiles, networks and their ACLs, then the project. Recovery does not
  restart OVS, chassis, the uplink, or central again.
- A provider-parent conflict is a separate infrastructure preflight failure.
  Fleet names the competing network, profile, or instance NIC and refuses
  convergence without deleting it. The sandbox reaper cannot repair that
  conflict.
- NB database backups are optional because the consumers are disposable;
  this is not a durability promise for long-lived workloads.
- Phase 3 observed guest MTU 1442 on the 1500-byte Geneve underlay. Forward
  paths may have a smaller operator-side MTU; later desktop and deployment
  work must qualify their actual paths.

### Confirmation

Phase 5 has established the infrastructure portion of this proposal:
OpenTofu produced a clean plan for the standalone central VM; the durable
central serves only mutual TLS; an issued client certificate completed
`ovn-nbctl show`; and a plaintext connection was refused. All four chassis
completed the TLS cutover. A subsequent 11-operation fleet dry run was a
no-op, and the transitional `sandbox01` central was purged through fleet.

The complete CA and all-five-leaf rotation also passed live. The sequence was
central stopped, `central-tls`, central running with the new CA, then fleet's
OVN client/chassis converge. NB_Global, SB_Global, and two logical-switch UUIDs
were preserved. The new `lab03` identity authenticated to both NB and SB; the
old identity was rejected by both before an authenticated response.

Phase 5 also exposed a stale in-memory trust failure after the OVN CA was
silently re-minted. Stored Incus configuration already named the new CA, but
the `lab01`, `lab02`, and `nas01` daemons continued reconnecting with the old
CA. Their failed handshakes filled the central VM's 20 GiB root filesystem.
After evidence capture and owner approval, recovery truncated only the three
identified log files and recycled those three Incus daemons serially. `lab03`
was left running because its daemon already held the new trust. All members
returned `Online`, central processes retained their PIDs and start times, and
the measured inbound reconnect rate fell from 1,039 per second to zero.

[Fleet PR #20](https://github.com/GilmanLab/fleet/pull/20) prevents the same
silent transition: the ceremony refuses to mint an absent CA unless the
operator supplies `--mint-ca`, delivery paths require the reviewed CA
fingerprint, an OVN converge reports changed in-memory trust, and the explicit
trust-roll operation restarts selected daemons one at a time with an online
gate. [Root PR #34](https://github.com/GilmanLab/root/pull/34) records the
evidence-first, approval-gated recovery procedure in the canonical runbook.

A cross-member fixture completed three of three pings on each tested path.
Public OpenTofu cloud-init metadata reconciliation was still pending
AWS authentication and is not part of that proof.

The application lifecycle acceptance run completed in 308.22 seconds. It
covered the dual-NIC router NAT path, forwards, native isolated OVN networks,
sandbox-local publication and clone, the approved snapshot-recreation
contract, and dependency-ordered deletion.

The final central-outage qualification also passed. With central stopped,
fleet accepted one receipt-backed reboot of `lab03`. Its management API was
unavailable from `02:34:27.844Z` until `02:36:19.475Z`, approximately 112
seconds, then the member returned `Online` and `Fully operational`. The
surviving `lab01`-to-`nas01` guest path completed three of three pings while
central was down and after the reboot. A guest on the rebooted member
completed zero of three during the outage, as expected.

A separate sandbox create during the outage left its owned `default` network
`Errored` while holding `10.10.40.65`. A reaper scan returned backend
unavailable in 480 ms and retained the expired project and network. Central
was then started once, with no other repair or restart. Both guest paths
recovered to three of three pings, and a later reaper scan removed all owned
fixture residue across all four members and all projects in 3.03 seconds. The
post-rotation and post-reboot fleet dry run proposed no changes in all 11
operations.

These checks establish the OVN infrastructure and lifecycle evidence recorded
here. They do not accept this decision or claim that Phase 9b validation is
complete. The record remains `proposed`; only the owner may change its status
to `accepted`.

## More Information

- [Agentcompute design](../designs/agentcompute.md)
- [Phase 3 qualification and parent recovery](https://github.com/GilmanLab/agentcompute/blob/spike/ovn-recreate-diagnosis/spikes/ovn/README.md): first post-fixture-deletion lab01-gateway cycle passed in 31.018 seconds, without reboot, central restart, or neighbor repair.
- [Incus #3985](https://github.com/lxc/incus/issues/3985): unavailable NB creation leaves an `Errored` network; deletion after central recovery releases it.
- [Incus #3986](https://github.com/lxc/incus/issues/3986): raw macvlan parent contention is separate from the central-outage failure.
- [Operate OVN central and certificates](../runbooks/ovn-central-and-certificates.md)
- [CVE-2026-40243 advisory](https://github.com/lxc/incus/security/advisories/GHSA-c839-4qxr-j4x3): patched in Incus 7.0.0 and later.
