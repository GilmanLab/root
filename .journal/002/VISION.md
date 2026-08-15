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
- **[OPEN]** Dependency inversion risk: `pikvm01` (gw01 Port 3) and `kvm01`
  (gw01 Port 4) get their network connectivity *from* `gw01` — the device they
  must rescue. If `gw01` is down, the KVM path may be unreachable unless
  `pikvm01`'s Wi-Fi (or cellular) fallback is configured. Needs an answer.
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
- `nas01`'s job: run storage-centric services — e.g., Garage as the lab's
  "cloud" object storage. `nas01` is accepted as more critical than
  `lab01`–`lab03` (something must host critical services; the compute nodes
  stay expendable). Because `nas01` is in the same Incus cluster, cold-moving
  critical services to a compute node remains a recovery option.

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

**[OPEN]** within this decision:

- Cluster template contents and tooling: what exactly constitutes a cluster
  (Talos version pinning, CNI choice, GitOps bootstrap, default storage class,
  LB integration) and what drives creation (Terraform/OpenTofu? scripts?).
- IPAM for ephemeral clusters: node IPs and LoadBalancer pools must be
  allocatable *without* hand-editing `gw01` per cluster, or the EKS-like
  friction goal fails. Likely shape: reserved workload supernet + BGP
  advertisement from clusters to `gw01`; undecided.
- Talos VM attachment: Incus bridge onto lab VLANs vs. OVN overlay.
- Garage data durability: `nas01` has 2x 1TB NVMe (and empty 3.5" bays?);
  what does Garage store onto, is it replicated anywhere, and what is the
  off-node/off-site backup story for critical data?
- Which NVMe is the IncusOS install target vs. the storage pool on each node
  (assumed: small drive = OS, large drive = pool — confirm; IncusOS wants
  ≥50GiB for the system).
- One-off VM inventory: which workloads are expected to bypass k8s.
- Cluster-creation machinery fork: CAPN (cluster-api native; adds a
  management-cluster chicken/egg) vs. OpenTofu with Incus + Talos providers
  (no CAPI, boring). Both real; undecided.
- Install-media delivery per node: MS-02s can take seeded ISOs via AMT
  virtual media; `nas01` has no AMT — PiKVM mass-storage emulation through
  the TESmart USB hub is unverified, may need direct USB for install day.
- Does the N5 Pro (`nas01`) satisfy IncusOS's TPM 2.0 + Secure Boot
  requirements? Verify before committing it to the cluster.
- Custody of IncusOS secrets: ZFS recovery keys + seed client certs must
  live outside the lab (Bitwarden?); undecided.

Candidate for ADR-0002 (compute platform layering) once the open points above
have settled enough to record.

## Known inconsistencies / holes (running list)

Resolved:

1. ~~UM760 role~~ — resolved: deliberately uncommissioned shelf spare.
2. ~~NAS 5GbE port~~ — resolved: connected to `sw-mgmt01` port 8; recorded as
   `PHY-019` in the cabling map (PR #8).
3. ~~Four-node quorum~~ — resolved by research: `cluster.max_voters` defaults
   to 3; a 4-node cluster runs 3 voters + 1 stand-by automatically.

Open:

3. OOB/recovery: wiring done but untested; console cabling undocumented;
   `pikvm01`/`kvm01` network dependency on `gw01` unresolved; AMT role and
   switch recovery paths undefined. See OOB / recovery section.
4. Upstream of the home router (WAN handoff, modem/ONT) — undocumented,
   deliberately deprioritized for now.
5. UPS management card exists but is not hooked up (TODO). Monitoring and
   shutdown coordination undefined. Idle load fine; full-load draw vs. 700W
   ceiling untested.
6. VP6630 Port 1 unconnected — reserved for anything?
7. ~~Canonical device naming~~ — resolved: registry merged in PR #8. Remaining:
   apply names to device identities and chassis labels.
8. Compute platform sub-questions — see Compute platform [OPEN] list (cluster
   template, IPAM/BGP, Talos VM attachment, Garage durability, disk roles).

## Decisions log (pointers)

- ADR-0001: VyOS = L3, dedicated switches = L2 (accepted 2026-08-14).
