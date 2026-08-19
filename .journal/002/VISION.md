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
- Design fiction to apply when judging choices: *a medium-sized company
  leaving AWS to stand up a bare-metal cloud in a colo.* Decisions should
  look sensible in that world, scaled down. Corollary: "we bought another
  machine — how does it get online quickly?" is a workflow that must have a
  good answer, and everything on bare metal is IncusOS (homogeneity is
  load-bearing).

## Core principles

**[DECIDED]** Present in everything built here; agents must default to these:

1. **GitOps first.** Git is the source of truth. Reach for a Git-driven
   mechanism before any imperative/manual one.
2. **Immutability and reproducibility.** Prefer image-based, declarative,
   rebuild-from-scratch-able systems. (This is exactly why IncusOS was chosen
   as the bare-metal hypervisor.)

### Secrets

**[DECIDED]** (2026-08-18) All **non-generated** secrets live in the
`GilmanLab/secrets` repo as an organized hierarchy of SOPS-encrypted files —
the GitOps mandate applied to secrets. Automation (TODO, later) keeps them in
sync with Vault. The mandate deliberately does NOT apply to ephemeral or
generated secrets.

**[DECIDED]** Root of trust: **AWS KMS + PGP**. The existing `alias/glab-sops`
KMS key in the `lab-admin` account (186067932323, us-west-2, key
`2aba1d94-6eaf-4d80-8d26-2077f32fd7c5`) is the backing key; hierarchy
*scoping* controls access via SOPS encryption context (`Repo` + `Scope`,
continuing the existing repo's convention). CI authenticates via GitHub
OIDC-assumed AWS roles whose IAM policies condition `kms:Decrypt` on the
encryption context — what CI can see is an IAM policy question. The
YubiKey-backed PGP key (offline master, subkeys on three YubiKeys, Josh sole
holder) is the human/disaster-recovery recipient. Inspiration:
`~/work/catalyst-infra` (same single-key + context-scope + grant-invariant
model; catalyst forbids non-KMS recipients — the lab deliberately differs by
keeping PGP).

**State of the world**: `GilmanLab/secrets` already exists (glab generation)
with KMS-only creation rules and scopes `network-tailscale`, `network-vyos`,
`keycloak`, `talos-platform`. The glab generation (session 026/027)
deliberately *removed* PGP/age recipients; adding PGP back is a **conscious
reversal** — rationale: the lab must be rebuildable if the AWS account is
lost. T33 is therefore *restructure*, not create: v2 hierarchy, add PGP
recipient to key groups, `sops updatekeys` sweep.

**Lineage note**: the earlier "no AWS in the old lab" audit examined
`~/code/lab`, which is v0 (ancient: age+YubiKey SOPS, iDrive e2). The actual
deprecated predecessor is **`~/code/glab`** (v1): full AWS substrate, the
existing secrets repo, `GilmanLab/infra`. Lab2 = v2.

**[OPEN]** residue (T33): generated-but-durable, lab-recovery-critical
secrets (IncusOS ZFS recovery keys, seed client key, factory cache-signing
key) need a home before Vault exists and independent of the lab being alive —
candidate: the secrets repo as a documented exception (mandate requires
non-generated there; doesn't forbid generated). Vault unseal custody recurs
later (T24).

Priority: restructure the repo soon — secrets production is imminent (T33).
Vault sync automation is explicitly later (T34).

### Image distribution

**[DECIDED]** The concrete realization of both principles: *configs written in
git → reproducibly built from pinned recipes → consumed by the things that
need them.* Reproducibility lives in the pinned recipe (config + base-image
checksum + tool version), not necessarily a persisted artifact. Three legs:

1. **IncusOS** (amended 2026-08-18): per-machine seed configuration lives in
   git (`GilmanLab/fleet`); the componere tooling builds **and burns/serves
   locally in a single step** — no OCI publish. Rationale: for this fleet the
   publish→pull→burn round trip adds work and creates a secrets-at-rest
   problem; single-step local render lets secrets flow from the SOPS-encrypted
   `GilmanLab/secrets` repo (or be generated at render) into the seed at
   burn time, existing nowhere at rest. CI on `fleet` *validates* seed
   rendering (schema checks, optional throwaway build) but publishes nothing.
   Runtime Incus configuration (pools, networks, profiles, VMs) is IaC via
   OpenTofu's Incus provider, in git.
2. **Talos**: self-hosted Sidero image-factory (T27, decided) — generic
   images, schematics in git, per-node identity injected by CAPN at instance
   create.
3. **Other VM images**: purpose-built bootc-style (defined in git, published
   via CI, pushed with imgoci) OR Fedora CoreOS + Ignition where the job is
   just a small container stack in a VM (VM isolation preferred over Incus
   containers for security). imgoci remains the distribution format for this
   leg.

~~T28 (secrets in published seeded images)~~ — dissolved by the leg-1
amendment: nothing seeded is published.

## Product vs. instance (componere & imgoci)

**[DECIDED]** GilmanLab is not a one-off: Josh is building a generalized OSS
"cloud" product, and the lab is that product applied to his hardware.

- **componere** (`~/code/componere`, meta-repo) — the general OSS bare-metal
  cloud product. Sub-repos (early; most still template scaffolding):
  - `incusos-builder` — active development; vendors the upstream `incus-os`
    mkosi tree as reference. This *is* the image-factory territory (T25).
  - `incus-vm-oci` — presumed: VM images distributed as OCI artifacts.
  - `incus-bootc` — presumed: container-image-driven (bootc-style) OS images
    for Incus.
  - `imgoci` — presumed: componere-side imgoci integration.
  (Presumed roles unconfirmed — Josh to correct.)
- **imgoci** (`~/code/imgoci`, meta-repo) — OS-image releases stored in OCI
  registries:
  - `spec` — the imgoci release-format specification (draft; CUE schema +
    conformance corpus; Community Spec licensed).
  - `bigoci` — mature Go library for multi-GB file push/pull to OCI
    registries (chunked, parallel, resumable; benchmarked; ~v0.1.0).
  - `go-oci-blob` — lower-level OCI blob transfer client.
  - `go` — canonical Go implementation of the spec (early).

Implication for agents: capabilities that overlap this suite (image building,
image distribution) belong in the *product* repos and get consumed by the lab
— don't build lab-local one-offs of them.

Working relationship (T26, **[DECIDED]** 2026-08-15):

- **Instance repo layout**: `GilmanLab/fleet` (private sub-repo, cloned via
  `init.sh`) holds *bare-metal-only* instance config: per-machine IncusOS
  seed configs and Incus configuration (incl. the OpenTofu Incus roots).
  Kubernetes-related config explicitly does NOT live there — the platform
  (management) cluster and spawned clusters get separate repos later,
  probably one for reusable code + one for GitOps. [PROVISIONAL on the k8s
  split shape]
- **Consumption contract**: the lab consumes product artifacts *pinned*
  (version/digest, pre-release allowed — the lab is componere's first-class
  test bed). No local forks/patches of product code; lab pain becomes an
  upstream issue/PR, then re-pin.
- **Flow is bidirectional**: capabilities are often developed lab-first,
  then *promoted* into componere once proven. Incubation in the instance is
  expected; permanence there is not.
- **Bootstrap does not need interim tooling**: `incusos-builder` is nearly
  done — the lab waits for it rather than hand-rolling seed/burn scaffolding.
- **Identity boundary**: product repos stay generic. Test for any change:
  "would a second componere user want this?" No → instance repo. Product
  defines config schemas; the instance supplies instances of them.

## AWS substrate (carried forward from glab/v1)

**[DECIDED]** The lab keeps a small AWS footprint as its out-of-lab anchor.
Account `186067932323` (profile `lab-admin`, SSO, us-west-2). Audited
2026-08-18 (GlabAwsMigrationAudit, session notes): **six** IaC roots in
`GilmanLab/infra` (glab generation), state bucket
`glab-lab-tfstate-186067932323` unless noted:

- `aws/lab-foundation` — VPC `172.16.0.0/16`, IGW/subnet/routes, private
  Route53 zone `glab.lol` (`Z009084217D5KKVQERJY3`), public zone
  `acme.glab.lol` (Cloudflare-delegated), the `alias/glab-sops` KMS key. LIVE.
- `aws/subnet-router` — EC2 Tailscale subnet router (own root, not part of
  foundation): instance, EIP, IAM role `glab-aws-subnet-router`, dns-mirror
  container via SSM. VyOS pulls the mirrored `glab.lol` zone from its
  hard-coded Tailscale IP `100.80.89.100`. LIVE.
- `aws/keycloak` — Flatcar EC2 + EBS Postgres data, `id.glab.lol`, and the
  **current** `glab-github-token-broker` Lambda (module v2.0.0); `labctl`
  invokes it at boot to read `GilmanLab/secrets`. LIVE.
  **[DECIDED]** (T36): **Zitadel** is v2's identity service; keycloak
  migrates as-is (live), follow-up destroy once Zitadel serves. JWT issuer
  `https://id.glab.lol/realms/lab` and the EBS volume are identity/data
  critical until then.
- `aws/github-token-broker` — **tombstone**: legacy root, partially
  destroyed (session 044); its state likely retains ONLY the GitHub Actions
  OIDC provider. NEVER ordinary-apply it (source still declares the
  destroyed resources). Migration = carve the OIDC provider into a small
  dedicated identity root via cross-state move/import, then retire.
- `security/pki/root-ca` — KMS-signed root CA (`alias/glab-pki-root-ca`,
  pathlen:2, key `5b585512…`), committed `root_ca.crt` bound to that key.
  LIVE. Warning: an obsolete same-named state object exists in the OLD
  account bucket (`gilmanlab-tfstate`, acct 340752822076) — never copy it.
- `network/tailscale` — Tailscale provider (MagicDNS, split DNS, federated
  identity for the subnet router, route approval); state is in the OLD
  account bucket via `aws-vault exec jmgilman-prod`. Needs backend migration
  to the lab bucket during the move.

**[DECIDED]** Migration (T35): all six roots move to a dedicated
`GilmanLab/aws` repo. Mechanics per audit: pure repo move — same backend
bucket/keys, same lock files, no `moved` blocks; acceptance = zero-diff plan
per root. Order: freeze + live read-only state capture → bootstrap repo (CI
covers all six; glab Moon CI omitted root-ca/tailscale) → resolve broker
tombstone (OIDC provider carve-out) → foundation → root-ca → tailscale
(backend migration) → subnet-router → keycloak → docs/ownership cutover,
single-writer enforced. Invariants: KMS ARNs, IAM role/function names,
hosted zones, `id.glab.lol`, Tailscale device identity all unchanged.
Open sub-question: does `network/tailscale` belong in `GilmanLab/aws` or in
`GilmanLab/networking` (where session 003 put the tailnet policy)?

Consequence adopted knowingly: AWS joins GitHub as a hard external
dependency — it is the secrets root of trust (KMS), the out-of-lab anchor for
state, DNS (`glab.lol`), and the site-to-site tailnet bridge. The PGP
recovery recipient exists precisely so total AWS loss is survivable.

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
   k8s. One *management cluster* is specified (below); all other clusters are
   cattle, EKS-style: no fixed list; the platform's job is to make spinning up
   a working cluster fast and repeatable.
3. **A few one-off VMs** directly on Incus for things that don't fit k8s.

### Management cluster and critical services

**[DECIDED]** One specified cluster exists: a Talos management cluster of
three nodes, initially all VMs on `nas01`, hosting the critical services:

| Service | Role |
| --- | --- |
| Zitadel | Identity |
| HashiCorp Vault | Secrets + PKI |
| Cluster API (CAPI) | The "EKS" mechanism — integrates with Incus/Talos to spawn clusters, driven by GitOps |

**[PROVISIONAL]** Likely later: additional management-cluster Talos nodes on
`lab01`–`lab03` so the cluster isn't wholly dependent on `nas01` staying
alive. Not designed yet — deliberately.

Note (accepted risk, worth stating): until that stretch happens, the
management cluster's three VMs share one failure domain (`nas01`) — etcd
quorum and Longhorn-style replication protect against VM-level failure only,
and everything above (identity, secrets, cluster factory) rides
on one box.

### Talos image plane

**[DECIDED]** (T27, 2026-08-15) Self-hosted **Sidero image-factory** is the
Talos image plane; no bespoke builder. Verified requirements: single Go
service (MPL-2.0), official Helm chart, OCI cache registry (GHCR), ECDSA
cache-signing key, cosign-verified pulls of Sidero source images from
ghcr.io. Provides schematics (declarative: Talos version + system
extensions, stored in git), ISO/disk/UKI assets, PXE frontend, and the
installer-registry frontend that Talos *upgrades* pull from.

Deployment notes (settled intent, details at deploy time):

- Runs on the management cluster as a *platform service* — second tier, not
  one of the critical three. Cold start uses the public factory.talos.dev;
  repoint clusters at the self-hosted factory once it's up (same
  product-of-bootstrap pattern as Vault).
- Talos VM images stay *generic*: per-node identity arrives via CAPN's
  cloud-init disk at instance create, not baked into images.
- Cache-signing key joins the secrets-custody family (T15).
- Needs a stable in-lab URL — depends on DNS/ingress decisions (open
  elsewhere); not a blocker for cold start.
- Schematic definitions are cluster-template inputs (T08) and live in git
  with the template.

### VM orchestration (T32 — the open fork)

Three lifecycle regimes; one is undecided:

- Cattle-cluster VMs: **[DECIDED]** CAPI/CAPN owns them (T09).
- Non-Talos one-off VMs (leg-3 bootc/CoreOS pets): **[DECIDED]** 2026-08-18 —
  **OpenTofu** owns them, as more resources in the same roots that own Incus
  runtime config. CAPI is categorically wrong (its object model is
  clusters); no Incus VM operator exists; plan/apply lifecycle matches pet
  VMs. (Future componere product idea, parked: a small controller
  reconciling VM CRs against the Incus API — passes the second-user test.)
- The 3 management-cluster Talos VMs: **[OPEN]** — the actual fork.

Candidates weighed 2026-08-18:

- **Crossplane — rejected.** Runs *in* k8s (cannot bootstrap the cluster it
  would run on) and post-bootstrap it duplicates CAPI with no first-class
  Incus provider (Upjet-wrapped TF provider only). Revisit only if a
  self-service claims UX is ever wanted product-side.
- **(a) OpenTofu**: official `lxc/terraform-provider-incus` + Talos provider
  create/bootstrap the mgmt VMs from a laptop. Zero new tools (tofu already
  owns Incus runtime config). Cost: mgmt cluster forever special — tofu
  describes it, CAPI describes everything else; day-2 = tofu+talosctl.
- **(b) CAPI self-managed (pivot pattern)**: temp kind cluster on a
  workstation runs CAPN against the Incus API → creates mgmt VMs → install
  CAPI into the new cluster → `clusterctl move` → mgmt cluster describes
  itself; one source of truth; upgrades/stretch (T21) become CAPI edits.
  Cost: bootstrap choreography, CAPN Talos template not-CI-tested,
  self-managed sharp edges (recovery = re-pivot from laptop).

Lean: **(b), spike-verified** — with an honest caveat recorded: tofu is in
the stack regardless (runtime config + one-off VMs), so (b)'s value is not
"one tool" but *cluster-fleet consistency* — every Talos cluster born,
upgraded, and stretched (T21) the same CAPI way. If the pivot spike is
anything but smooth, (a) wins on simplicity. Spike needs no lab hardware:
kind + CAPN + any Incus daemon (the shelved UM760 is a natural sacrificial
host).

Rides along either way: OpenTofu **state backend** — answered by the AWS
substrate: the existing `glab-lab-tfstate-186067932323` bucket (lab-admin
account) is the backend; out-of-lab, no bootstrap circularity. (Earlier
iDrive-e2 candidate withdrawn — that was v0's storage, and a real bucket
already exists.)

### Bootstrap sequence

**[PROVISIONAL]** Josh's intended flow:

1. Install IncusOS on `nas01` (delivery options under investigation — T14).
2. Spawn the three initial Talos management-cluster nodes as Incus VMs.
3. Set up/deploy the critical services (exact mechanism TBD; Josh has a
   working idea).
4. `lab01`–`lab03` get IncusOS via AMT-mounted seeded ISOs and join the
   Incus cluster (`incus cluster join`).
5. Future clusters are spawned via GitOps-applied CAPI resources.

Resolved 2026-08-15 (T20): Tinkerbell dropped from the critical services.
The fleet is homogeneous IncusOS with no netboot path; AMT virtual media +
the factory-reset API cover onboarding and reprovisioning natively. iPXE
likewise rejected (no published netboot artifacts; UEFI ISO-chainload
flakiness; Secure Boot key conflicts) — revisit only if upstream ships a
supported netboot path. Sneakernet elimination: AMT covers `lab01`–`03`;
`pikvm01` mass-storage emulation may cover `nas01` (verify in T01).

### Seeding & install mechanics (researched 2026-08-14, primary sources)

Full brief: `IncusSeedResearch` (session 002 notes). Load-bearing facts:

- **Seed = uncompressed tar** in the image's `seed-data` partition. Sections
  (YAML/JSON, strict schemas — unknown fields fail): `install` (incl. disk
  `target` selection by bus/id/size/sort, `force_install`), `applications`,
  `incus` (full Incus `InitPreseed`: trust certs, pools, networks, profiles,
  cluster join fields), `network` (full static config: interfaces bound by
  MAC via `strict_hwaddr`, bonds, VLANs, addresses, routes, roles
  `management|cluster|instances|storage`), `update`, `kernel`, `security`
  (**`encryption_recovery_keys` can be pre-set** → T15), `provider`,
  `services`, `certificates/*.crt`.
- **Headless/CI image production is official**: `flasher-tool --image <iso|img>
  --seed <tar>` injects non-interactively. Reproducibility = pin image
  checksum + flasher version + deterministic tar. GitOps-compatible: seed
  templates in git, CI renders per-node images (only *public* client cert in
  seed; private key stays out).
- **Recommended shape: 4 images from one template set** — common sections +
  per-node `network.yaml` (hostname, static addrs, MAC-bound interfaces).
  Bootstrap node `apply_defaults: true`; joiners `apply_defaults: false`
  (required — join refuses members with existing networks/pools).
- **Cluster formation**: post-boot `incus remote add` each node →
  `incus cluster enable` on node 1 → `incus cluster join` per joiner (issues
  its own token; local ZFS answers are `local/incus`). Fully-preseeded join is
  technically possible but not the blessed path (embeds short-lived tokens in
  images).
- **Network pre-seeding works**: node boots reachable on seeded static config
  with zero console interaction. AMT-shared NIC caveat (issue #705): leave
  roles off the AMT-shared interface; keep management/cluster on the primary.
- **Delivery**: ISO is *non-hybrid* — virtual-CD (AMT) only; USB needs the
  IMG written raw. MS-02s: AMT virtual CD with `force_reboot: false` (installer
  waits for media removal). `nas01`: USB stick, one-time manual — acceptable.
- **Reprovisioning without media**: `incus admin os system factory-reset`
  API wipes apps/config/data pool, resets TPM state, writes *new seeds*, and
  reboots — a built-in rebuild-from-seed loop on an installed node. Full
  image reinstall = boot seeded media with `force_install: true` (AMT-remote
  on MS-02s).
- **Operations Center** (v0.8.1, pre-1.0): can do token-based pre-seeded
  images, auto-registration, central cluster formation — assessed as too much
  machinery for a one-time 4-node bootstrap; adopt deliberately later if
  fleet-control-plane is the goal.

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
| T01 | OOB verification pass: pikvm01 reaches/controls all 5 hosts incl. kvm01 channel switching; also test pikvm01 mass-storage (virtual USB) emulation through kvm01 — it would eliminate USB sneakernet for `nas01` installs | open | Hands-on test session |
| T02 | Console cabling reference in docs site (KVM chain is undocumented) | open | Fold into next docs PR |
| T03 | AMT role vs. KVM chain; switch recovery paths (no KVM inputs) | open | Decide during OOB design |
| T04 | UPS: connect mgmt card; define monitoring + shutdown ordering | open | Hardware task, then design |
| T05 | Full-load power draw vs. 700W UPS ceiling | open | Measure once compute runs real load |
| T06 | Apply canonical names to device identities + chassis labels | open | Network gear likely session 001 |
| T07 | `gw01` Port 1 unconnected — reserved purpose? | open | Josh to answer, low stakes |
| T08 | Cluster template contents (Talos version, CNI, bootstrap, storage class, LB) | open | Design after T14/T20 spikes |
| T09 | ~~Cluster-creation machinery~~ | resolved | CAPI it is (Josh: CAPI is the EKS mechanism, GitOps-driven); CAPN not-CI-tested risk stands — spike before trusting |
| T10 | IPAM for ephemeral clusters (workload supernet + BGP to `gw01`?) | open | Coordinate with session 001 addressing |
| T11 | Talos VM attachment: bridged VLANs now; OVN needs external DB (revisit when IncusOS hosts OVN central) | resolved-for-now | Bridged VLANs |
| T12 | Disk roles per node: seed `install.target` (bus/id/min/max_size/sort_order) selects install disk deterministically — encode small-NVMe target in seed | open | Encode in seed templates |
| T13 | `nas01` TPM 2.0 + Secure Boot capability for IncusOS | open | Verify in BIOS before cluster commit |
| T14 | ~~IncusOS seeding/bootstrap deep-dive~~ | resolved | Research done; facts in Seeding & install mechanics. Next deliverable: bootstrap design draft |
| T15 | ~~Secrets custody model~~ | resolved | Superseded 2026-08-18 by the SOPS model (see Secrets section): non-generated secrets → `GilmanLab/secrets`; residue questions moved to T33 |
| T16 | Garage / object storage design + critical-data backup story | deferred | Josh deferred entirely |
| T17 | One-off VM inventory (what bypasses k8s) | deferred | Emerges with usage |
| T18 | Upstream-of-`rtr01` documentation (WAN/modem) | deferred | Low priority per Josh |
| T19 | Move 5x 3TB WD Red from old Synology into `nas01` bays, wipe old RAID | open | When storage design is ready |
| T20 | ~~Tinkerbell's seat~~ | resolved | Dropped (Josh 2026-08-15); critical services are Zitadel, Vault, CAPI. iPXE also rejected — no upstream netboot path; AMT + pikvm01 MSD cover media delivery |
| T21 | Management-cluster stretch onto lab01–03 (escape single-`nas01` failure domain) | deferred | Josh explicitly not thinking that far ahead |
| T22 | GitOps engine choice (Flux vs. Argo etc.); Git home effectively GitHub (GHCR publishing implies it) — internet becomes a hard cold-start dependency, accept explicitly | open | Engine + consequence ruling |
| T23 | ~~Tinkerbell network requirements~~ | resolved | Moot — Tinkerbell dropped (T20); no DHCP/PXE VLAN needed |
| T24 | Vault bootstrap + DR: unseal strategy, backup, and what depends on Vault during cold start | open | Design with bootstrap flow |
| T25 | IncusOS image tooling → product-side: `componere/incusos-builder` (active dev). Parked opinions: pinned `flasher-tool` wrapping; upstream `incus-osd/api/seed` types; deterministic build. Amended 2026-08-18: build + burn/serve locally in one step, **no OCI publish**; `fleet` CI validates rendering only | in-progress | Product-side work; lab consumes it |
| T26 | ~~Product/instance boundary~~ | resolved | Ruled 2026-08-15: `GilmanLab/fleet` = bare-metal-only instance repo; k8s config in separate later repos (reusable code + gitops); pinned pre-release consumption OK; lab-first-then-promote flow; wait for incusos-builder (no interim tooling); generic-product boundary test. See Product vs. instance section |
| T27 | ~~Talos image plane~~ | resolved | Adopted 2026-08-15: self-hosted Sidero image-factory; bespoke builder dead; generic images + CAPN-injected identity. See "Talos image plane" section |
| T28 | ~~Secrets in published seeded images~~ | resolved | Dissolved 2026-08-18: IncusOS images are never published — single-step local build+burn; secrets flow from the SOPS secrets repo into the seed at burn time, nowhere at rest |
| T29 | bootc-style + Fedora CoreOS image lines for one-off VMs (defined in git, CI-published, imgoci-pushed) | deferred | Later product work; captured for context |
| T30 | Create `GilmanLab/fleet` private sub-repo (bare-metal instance config: IncusOS seeds, Incus/OpenTofu roots) and wire into `init.sh` | open | Actionable once first seed configs exist to hold |
| T31 | Deploy self-hosted image-factory on mgmt cluster (Helm; GHCR cache namespace; ECDSA signing key → custody; repoint clusters from factory.talos.dev) | open | After mgmt cluster exists; depends on DNS/ingress decisions |
| T32 | Mgmt-cluster Talos VM orchestrator: OpenTofu vs. CAPI-self-managed-pivot (Crossplane rejected; non-Talos one-off VMs decided → OpenTofu). Lean (b) CAPI pivot for cluster-fleet consistency, spike-verified; UM760 as sacrificial spike host; tofu state backend decision rides along | open | Spike, then rule — see VM orchestration section |
| T33 | Restructure existing `GilmanLab/secrets` for v2 — **priority, secrets production imminent**: v2 hierarchy; keep KMS+context-scope model (`alias/glab-sops`, `Repo`+`Scope`); add YubiKey PGP back as recovery recipient (conscious reversal of glab KMS-only decision) + `sops updatekeys`; per-scope OIDC role/IAM grants for CI; decide generated-durable exception | open | Wants migration audit (T35) context; then execute |
| T34 | Secrets→Vault sync automation | deferred | Explicitly later (TODO per Josh) |
| T35 | Migrate all SIX roots to `GilmanLab/aws` preserving tfstate (audit done — plan in AWS substrate section): lab-foundation, subnet-router, keycloak, broker tombstone (OIDC carve-out only), root-ca, network/tailscale (backend migration from old account). Precondition: live read-only state capture with fresh `lab-admin` SSO. Sub-question: tailscale root's repo home (aws vs. networking) | open | Ready to execute as implementation work; Josh to green-light + rule tailscale home |
| T36 | ~~Identity service~~ | resolved | Zitadel (Josh 2026-08-18; had forgotten the hosted Keycloak). Keycloak migrates as live infra, follow-up destroy once Zitadel serves (tracked inside T35 + future teardown task) |
| T37 | Systematic glab (v1) carry-forward audit beyond AWS: labctl, DNS mirror, VyOS configs, Talos platform cluster remnants, docs architecture pages — what migrates, what dies | open | After T35; candidate researcher task |

Resolved history: UM760 = shelf spare · NAS 5GbE = `sw-mgmt01` port 8
(PHY-019, PR #8) · naming registry (PR #8) · 4-node quorum non-issue
(3 voters + 1 stand-by) · `pikvm01` break-glass = local console at the rack ·
Tinkerbell + iPXE rejected for provisioning (T20/T23).

## Decisions log (pointers)

- ADR-0001: VyOS = L3, dedicated switches = L2 (accepted 2026-08-14).
