# GilmanLab v2 — Vision & Context

Working document. Purpose: give any agent enough context to work on the lab
without re-interviewing Josh. Every statement is tagged by confidence:

- **[DECIDED]** — settled; agents may rely on it. ADRs/designs are canonical where linked.
- **[PROVISIONAL]** — current thinking; may change; check before building on it.
- **[OPEN]** — known hole; do not assume an answer.

Canonical docs live in the `docs/` sub-repo (MkDocs site). This file holds the
vision, rationale, and everything not yet promoted into real docs.

---

## Purpose of the lab

**[DECIDED]** The personal on-prem cloud of a Senior SRE.

A personal playground for trialing new software, paradigms, and architectures —
and an opinionated expression of what Josh believes is the *correct* way to run
a bare-metal setup. Implications agents should internalize:

- The lab is the product. Building it well *is* the point; production-grade
  discipline (IaC, version control, verification, recovery paths) is a goal,
  not overhead.
- Experimentation is first-class: expect churn in workloads. The foundation
  (network, compute platform, storage) should be stable; what runs on top is
  deliberately volatile.
- Bleeding-edge choices are a feature, not a risk to argue against — flag
  maturity risks, don't veto them.

## Device naming

**[DECIDED]** Approved by Josh 2026-08-14; shipped in PR #8. Canonical
registry: `docs/docs/reference/naming.md`.

Rules:

- Every commissioned device gets exactly one canonical name. That name is the
  device's system identity (hostname / RouterOS identity / web-UI system name),
  its physical chassis label, and the only identifier used in docs and configs.
- Names are lowercase, DNS-safe labels (`a-z`, `0-9`, `-`), role-based, with a
  zero-padded two-digit ordinal.
- Uncommissioned hardware (shelf spares) has no name; the inventory refers to
  it by model. Names are assigned at commissioning.
- Repurposing a device means renaming it. Fleet is ~10 devices; the registry
  makes that a mechanical sweep.

Registry:

| Name | Device | Role |
| --- | --- | --- |
| `gw01` | Protectli VP6630 (VyOS) | Lab gateway |
| `rtr01` | MikroTik CRS309 #1 | Home router / internet edge |
| `sw-core01` | MikroTik CRS309 #2 | Core L2 switch |
| `sw-mgmt01` | TRENDnet TEG-3102WS | Management/OOB switch |
| `lab01`–`lab03` | Minisforum MS-02 Ultra x3 | Compute nodes |
| `nas01` | Minisforum N5 Pro | NAS |
| `pikvm01` | PiKVM V4 Plus | KVM-over-IP |
| `kvm01` | TESmart 8x1 HDMI KVM | Console switch |
| `ups01` | APC Smart-UPS SMT1000 | UPS |
| — | Minisforum UM760 | Shelf spare, unnamed until commissioned |

All other docs (inventory, cabling map, designs) reference devices by
canonical name. Setting the identity on each physical device (hostnames,
RouterOS identity, chassis labels) is a pending implementation task.

## Hardware (summary — canonical: docs/reference/hardware-inventory.md)

| Device | Qty | Role | Status |
| --- | --- | --- | --- |
| Protectli VP6630 (2x SFP+, 4x 2.5GbE) | 1 | Lab gateway, VyOS | [DECIDED] ADR-0001 |
| MikroTik CRS309-1G-8S+IN | 1 | Core L2 switch (lab VLANs) | [DECIDED] ADR-0001 |
| MikroTik CRS309-1G-8S+IN | 1 | Home router / internet edge | [DECIDED] per design draft |
| TRENDnet TEG-3102WS (8x 2.5G + 2x SFP+) | 1 | Management/OOB switch for MS-02s | [DECIDED] ADR-0001 |
| Minisforum MS-02 Ultra (Ultra 9 285HX, 64GB, 2TB+128GB NVMe, 2x 25G SFP+, 2x 2.5G, vPro/AMT) | 3 | IncusOS compute nodes `lab01`–`lab03` — expendable by design | [DECIDED] |
| Minisforum N5 Pro NAS (Ryzen AI 9 HX PRO 370, 32GB, 2x 1TB NVMe + 128GB OS, 10GbE+5GbE) | 1 | IncusOS node `nas01` — storage-centric services (e.g., Garage); accepted as more critical than lab01–03 | [DECIDED] |
| Minisforum UM760 (Ryzen 7, 32GB, 1x 2.5GbE) | 1 | Shelf spare — deliberately uncommissioned | [DECIDED] (for now) |
| PiKVM V4 Plus + TESmart 8x1 HDMI KVM | 1+1 | OOB console access | wired (untested); see OOB section |
| APC Smart-UPS SMT1000 (700W) | 1 | Power | mgmt card present, not hooked up (TODO); shutdown story [OPEN] |

## Networking (canonical: ADR-0001 + designs/drafts/lab-v2-core-network.md)

- **[DECIDED]** VyOS owns all L3: lab gateways, firewall, source NAT for internet
  egress. Switches are pure L2. Home→lab routed without NAT.
- **[DECIDED]** Physical topology per docs/reference/networking/physical-connections.md:
  each MS-02 has 2x SFP+ to core switch and 2x 2.5G to TEG-3102WS (mgmt/OOB).
  NAS 10G to core switch, NAS 5G to TEG-3102WS port 8. TEG uplinks to VP6630.
- **[PROVISIONAL]** Address/VLAN allocation, DHCP/DNS/NTP ownership explicitly
  out of scope of current docs — nothing decided yet.
- Note: MS-02 SFP+ ports are 25G-capable but CRS309 is 10G — links run at 10G.
  Expected, not a fault.

## OOB / recovery

- **[DECIDED]** Console wiring is installed but untested: `kvm01` inputs carry
  `lab01`–`lab03`, `nas01`, and `gw01` (5 of 8 inputs used). `pikvm01`'s
  HDMI/USB connect to `kvm01`'s console side, so `pikvm01` reaches any of the
  five hosts through `kvm01` channel switching.
- **[OPEN]** Not yet documented in the docs site (cabling map covers network
  cables only) — queue a console-connections reference.
- **[OPEN]** Verification pass: prove `pikvm01` can reach and control each
  host, including `kvm01` channel switching (likely via its LAN/RS232 control
  path).
- **[DECIDED]** Break-glass path: `pikvm01` has a local monitor/keyboard/mouse
  attached for non-network access. The `pikvm01`/`kvm01` network dependency on
  `gw01` is accepted — if `gw01` is down, recovery is physical presence at the
  local console.
- **[OPEN]** Role of MS-02 vPro/AMT vs. the KVM chain (power control, BIOS
  access); recovery paths for the switches (no KVM inputs).

## Compute platform

**[DECIDED]** Layered:

1. **IncusOS on bare metal, one 4-node Incus cluster** — `lab01`–`lab03` *and*
   `nas01` all run IncusOS and form a single Incus cluster. (IncusOS =
   immutable, image-based OS managed exclusively through the Incus API; no
   SSH, no package manager.)
2. **Talos Linux Kubernetes clusters as Incus VMs** — most workloads land in
   k8s. Clusters are cattle, EKS-style: no fixed cluster list; the platform's
   job is to make spinning up a working cluster fast and repeatable.
3. **A few one-off VMs** directly on Incus for things that don't fit k8s.

**[DECIDED]** Storage philosophy: no hyperconverged storage.

- Each node's non-OS NVMe is its local Incus storage pool.
- In-cluster data reliability comes from k8s-layer replication
  (Longhorn-style PVC replication across node boundaries).
- `nas01`'s job: run storage-centric services. `nas01` is accepted as more
  critical than `lab01`–`lab03` (something must host critical services; the
  compute nodes stay expendable).
- Bulk capacity plan: 5x ~3TB WD Red drives from Josh's old Synology NAS will
  move into `nas01`'s five bays; the old RAID gets wiped at that point.
  Timing: when we're ready, not yet scheduled. [PROVISIONAL]
- Object storage (Garage) and the critical-data durability/backup story:
  **deferred** — deliberately undesigned for now.

**[DECIDED]** Investment priority: a repeatable cluster *template* (the "EKS
experience") — specify a Talos cluster's makeup once (machine config, CNI,
bootstrap, LB/ingress integration, storage class) so clusters can be
copy/paste created and destroyed.

### Platform facts (researched 2026-08-14, primary sources)

- IncusOS GA since 2025-11-07. Rolling release: `stable` channel updates
  ~weekly, nodes check every 6h; A/B image slots, reboot into prior slot to
  roll back. Maintenance windows and `auto_reboot` configurable.
- Hard requirements: x86_64_v3, UEFI Secure Boot, TPM 2.0, ≥50GiB storage,
  wired NIC. Degraded modes (SB off *or* swtpm) exist but are second-class.
  Installer key enrollment can wipe vendor UEFI keys — retain Microsoft CA
  keys or add-in NIC option ROMs may break.
- Install: seeded ISO/IMG only (seed carries config + initial trusted client
  cert). No PXE path documented. No SSH ever; first contact is
  `incus remote add` against the console-displayed IP.
- Recovery: fallback API listener on console-displayed port; A/B boot;
  encrypted-ZFS recovery keys; lost-all-certs procedure needs console access
  + recovery key + temporary SB disable. **Recovery keys and seed certs are
  secrets that must be custodied outside the lab.**
- Storage: encrypted local ZFS is first-class. Running Ceph daemons *on*
  IncusOS is not supported yet (planned ~2026.09); only external
  Ceph/LINSTOR clients. → the no-hyperconverged decision is also the only
  supported option today; convenient alignment.
- Clustering: supported via remote `incus cluster enable`/`join` (joiners
  installed without default networks/storage). `cluster.max_voters` defaults
  to 3 → a 4-node cluster is 3 voters + 1 stand-by automatically. Upgrades:
  all members to same Incus version, evacuate/restore per node.
- OVN: IncusOS ships chassis support only; OVN *central* services on IncusOS
  are future work → OVN today requires an external OVN DB. Bridged VLAN
  attachment is the boring supported path for now.
- Talos on Incus: no Talos `incus` platform — use `nocloud` with Incus's
  cloud-init disk as transport (user-data = Talos machine config). Official
  CAPN (cluster-api-provider-incus) has a Talos template (tested Talos
  v1.12.2; latest is v1.13) but it is not CI-tested and its HAProxy LB is
  eval-only. Known gotcha: template recommends BIOS boot ("UEFI boot seems
  to not work correctly") and matching `security.secureboot` off.
- Nested virt not needed: Talos VMs are plain KVM guests.

**[OPEN]** within this decision — tracked in the Tracker below (T08–T15).

Candidate for ADR-0002 (compute platform layering) once the open points above
have settled enough to record.

## Tracker

Single source of truth for parallel items. Josh tackles a few at a time; the
agent maintaining this doc keeps statuses current. Statuses: `open`,
`in-progress`, `deferred`, `resolved`.

| ID | Item | Status | Next action / note |
| --- | --- | --- | --- |
| T01 | OOB verification pass: pikvm01 reaches/controls all 5 hosts incl. kvm01 channel switching | open | Hands-on test session |
| T02 | Console cabling reference in docs site (KVM chain is undocumented) | open | Fold into next docs PR |
| T03 | AMT role vs. KVM chain; switch recovery paths (no KVM inputs) | open | Decide during OOB design |
| T04 | UPS: connect mgmt card; define monitoring + shutdown ordering | open | Hardware task, then design |
| T05 | Full-load power draw vs. 700W UPS ceiling | open | Measure once compute runs real load |
| T06 | Apply canonical names to device identities + chassis labels | open | Network gear likely session 001 |
| T07 | `gw01` Port 1 unconnected — reserved purpose? | open | Josh to answer, low stakes |
| T08 | Cluster template contents (Talos version, CNI, bootstrap, storage class, LB) | open | Design after T14 spike |
| T09 | Cluster-creation machinery: CAPN vs. OpenTofu (Incus+Talos providers) | open | Spike both? Lean OpenTofu |
| T10 | IPAM for ephemeral clusters (workload supernet + BGP to `gw01`?) | open | Coordinate with session 001 addressing |
| T11 | Talos VM attachment: bridged VLANs now; OVN needs external DB (revisit when IncusOS hosts OVN central) | resolved-for-now | Bridged VLANs |
| T12 | Disk roles per node: confirm small NVMe = IncusOS, large = pool | open | Confirm at install time |
| T13 | `nas01` TPM 2.0 + Secure Boot capability for IncusOS | open | Verify in BIOS before cluster commit |
| T14 | IncusOS seeding/bootstrap deep-dive | in-progress | Research running; Josh wants depth here |
| T15 | Secrets custody: ZFS recovery keys + seed client certs outside the lab (Bitwarden?) | open | Decide alongside T14 |
| T16 | Garage / object storage design + critical-data backup story | deferred | Josh deferred entirely |
| T17 | One-off VM inventory (what bypasses k8s) | deferred | Emerges with usage |
| T18 | Upstream-of-`rtr01` documentation (WAN/modem) | deferred | Low priority per Josh |
| T19 | Move 5x 3TB WD Red from old Synology into `nas01` bays, wipe old RAID | open | When storage design is ready |

Resolved history: UM760 = shelf spare · NAS 5GbE = `sw-mgmt01` port 8
(PHY-019, PR #8) · naming registry (PR #8) · 4-node quorum non-issue
(3 voters + 1 stand-by) · `pikvm01` break-glass = local console at the rack.

## Decisions log (pointers)

- ADR-0001: VyOS = L3, dedicated switches = L2 (accepted 2026-08-14).
