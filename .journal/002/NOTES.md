---
id: 002
title: New session (goal pending)
started: 2026-08-14
---

## 2026-08-14 17:43 — Kickoff
Goal for the session: not yet stated; user requested a fresh session and will provide the task next.
Current state of the world: master at 3bcd8c0 (docs standardization PR #2 merged); session 001 (Lab v2 core networking) is in-progress in parallel; journal worktree at .wt/journal-jmgilman in sync with origin.
Plan: await the user's first request, then update this entry with the concrete goal.


## 2026-08-14 17:50 — Goal stated
Role: intelligent partner / sounding board. Capture Josh's homelab plan/vision
into a working document in this session folder (.journal/002/) that other
agents can use as shared context during lab build-out. Pain points driving
this: constant repetition across agents, and holes/inconsistencies surfacing
in the thinking itself. Free to research, spike, and probe assumptions.
Plan: iterative dump-and-refine sessions into a living doc; challenge
inconsistencies as they appear; keep structure light (agile, not waterfall).

## 2026-08-14 21:28 — Naming decided; docs PR #8 merged
Reviewed docs/ (inventory, ADR-0001, core-network draft, cabling map) and
seeded VISION.md in this folder. Josh resolved several holes: UM760 =
uncommissioned shelf spare; NAS 5GbE → TEG port 8; UPS mgmt card present but
unhooked (TODO); upstream-of-home-router docs deprioritized.
Decided: canonical role-based device names (gw01, rtr01, sw-core01, sw-mgmt01,
lab01-03, nas01, pikvm01, kvm01, ups01; UM760 unnamed until commissioned).
Shipped PR #8 (squash 3b9482a): new reference/naming.md, name sweep across
networking docs + design draft (ADR-0001 left untouched per MADR immutability),
PHY-019 added for nas01 5G link. Strict mkdocs build passed.
Next: continue vision dump — lab purpose and compute platform still [OPEN];
device-identity rollout (hostnames/labels) pending as implementation work.

## 2026-08-14 21:54 — Vision dump: purpose, compute, OOB; research folded in
Purpose decided: "personal on-prem cloud of a Senior SRE" — lab is the
product; foundation stable, workloads volatile; bleeding-edge welcome.
Compute decided: 4-node IncusOS cluster (lab01-03 + nas01); Talos k8s
clusters as Incus VMs, EKS-style cattle with a repeatable cluster template
as the investment priority; few one-off VMs; no hyperconverged storage —
local NVMe pools + k8s-layer replication (Longhorn-style); nas01 runs
storage-centric services (Garage) and is accepted as more critical.
OOB: kvm01 wired to lab01-03/nas01/gw01, pikvm01 into kvm01 — untested.
Flagged: cold-move claim invalid for node *failure* (local storage dies with
the node) — proposed distributed Garage across all 4 nodes as alternative;
pikvm01/kvm01 network hangs off gw01 (dependency inversion, Wi-Fi fallback?).
IncusOsResearch brief (agent://IncusOsResearch) key facts folded into
VISION.md: IncusOS GA 2025-11, SB+TPM2 required, seeded ISO/IMG install (no
PXE, no SSH), Ceph-on-IncusOS unsupported until ~2026.09, OVN central not
hosted yet (bridge VLANs for now), Talos via nocloud + cloud-init disk
(CAPN template exists, not CI-tested, BIOS-boot gotcha), 4-node quorum a
non-issue. New opens: N5 Pro TPM/SB verification, install-media delivery
for nas01 (no AMT), secrets custody for recovery keys/seed certs, CAPN vs
OpenTofu machinery.
Next: Josh to answer Garage shape/backup, pikvm01 Wi-Fi fallback intent,
N5 Pro bays plan; then consider ADR-0002 draft.

## 2026-08-14 22:04 — Tracker established; Josh's answers recorded
Josh asked the agent to own item tracking (too many parallel threads).
VISION.md holes list restructured into a Tracker table (T01–T19) with
statuses open/in-progress/deferred/resolved.
Answers: Garage + critical-data backup story deferred entirely (T16).
pikvm01 break-glass = local monitor/kb/mouse at the rack; gw01 network
dependency accepted (resolved). nas01 bulk capacity: 5x ~3TB WD Red from old
Synology going into the five bays, old RAID to be wiped when ready (T19).
Seeding/bootstrap (T14) is Josh's chosen next deep-dive: spawned
IncusSeedResearch (seed schemas, image production/CI, cert story, cluster
bootstrap sequencing, network pre-seeding, AMT delivery, Operations Center
maturity, reseeding). Results to fold into VISION.md and likely a bootstrap
design draft.

## 2026-08-14 22:17 — Management cluster, critical services, bootstrap flow
Josh revised: one specified cluster after all — Talos management cluster,
3 VMs on nas01, hosting critical services: Zitadel (identity), Vault
(secrets/PKI), Tinkerbell (provisioning), CAPI (the EKS mechanism, GitOps-
driven). Likely later stretch onto lab01-03; explicitly not designed yet.
Core principles recorded: GitOps first; immutability + reproducibility.
Bootstrap sequence (provisional): IncusOS on nas01 → 3 Talos VMs → critical
services → Tinkerbell provisions lab01-03 → CAPI spawns future clusters.
T09 resolved: CAPI. New: T20 Tinkerbell→IncusOS delivery tension (no PXE
path documented; SB key enrollment may break HookOS netboot), T21 mgmt
stretch (deferred), T22 GitOps engine + Git home, T23 Tinkerbell DHCP/PXE
network needs (session 001 coordination), T24 Vault bootstrap/DR.
Accepted risk noted: mgmt cluster = single nas01 failure domain until
stretched.

## 2026-08-14 22:25 — Seed research folded in (T14 resolved)
IncusSeedResearch brief (45KB, full text at history://IncusSeedResearch)
distilled into VISION.md "Seeding & install mechanics". Headlines: seed =
tar in seed-data partition, strict YAML schemas (install/applications/
incus-InitPreseed/network/update/kernel/security/provider/services/certs);
official headless injection via flasher-tool --image --seed (CI-able, pin
checksums); 4 images from one template set with per-node network.yaml
(MAC-bound, static addrs; bootstrap apply_defaults:true, joiners false);
post-boot cluster enable/join is the blessed path; AMT virtual CD for
MS-02s (force_reboot:false), USB IMG for nas01; encryption recovery keys
seedable (T15 shape: generate → seed → Bitwarden); factory-reset API =
rebuild-from-seed loop without media. OC v0.8.1 assessed too heavy for
one-time 4-node bootstrap.
T14 resolved. T12 sharpened (install.target in seed). T20 reframed: with
factory-reset + AMT reinstall, Tinkerbell may not earn its critical seat —
Josh to re-justify or drop.
Next: Josh reacts to bootstrap sketch; then draft designs/drafts bootstrap
design + likely ADR-0002.

## 2026-08-14 22:36 — Colo frame; image factory intent; Tinkerbell verdict pending
Josh's design fiction captured in VISION.md purpose: "medium company leaving
AWS for a colo bare-metal cloud"; new-machine onboarding must have a good
answer; bare metal is IncusOS-only (homogeneity load-bearing).
Josh intends a bespoke image factory (config → seeded ISO) — T25 opened with
design sketch (thin wrapper on flasher-tool, Go + upstream seed API types,
deterministic tar, render-time secrets, CLI-first).
T20 updated: recommended dropping Tinkerbell (homogeneous fleet + factory-
reset/AMT cover the loop; OC is the vendor-native MaaS path at scale);
awaiting Josh's ruling. T23 moot if dropped.

## 2026-08-15 12:43 — Product/instance split revealed (componere & imgoci)
Josh disclosed ~/code/componere (generalized OSS cloud product; GilmanLab =
that product on his hardware) and ~/code/imgoci (OS-image releases in OCI
registries). Surveyed both meta-repos: componere/incusos-builder in active
dev (vendors upstream incus-os mkosi tree) = the image factory; incus-vm-oci,
incus-bootc, componere/imgoci still template scaffolds (roles presumed,
unconfirmed). imgoci/spec = draft release-format spec (CUE + conformance);
bigoci = mature chunked large-file OCI transfer lib (~v0.1.0); go-oci-blob
lower-level; imgoci/go = canonical impl, early.
VISION.md: new "Product vs. instance" section with agent implication (image
build/distribution belongs product-side; lab consumes). T25 → in-progress,
product-side. T26 opened: product/instance boundary + interim-manual vs
block-on-product bootstrap ruling.

## 2026-08-15 12:53 — OCI-backed distribution vision captured
Josh's distribution vision recorded in VISION.md under Core principles:
configs in git → CI publishes reproducible/tagged OCI artifacts → consumers
fetch. Legs: (1) IncusOS seed configs in git, seeded images to GHCR, burn
tool product-side; runtime Incus config via OpenTofu Incus provider; (2)
Talos builder TBD + CAPI integration research (T27; flagged: CAPN injects
config at create → generic images may suffice; Sidero image-factory is
self-hostable); (3) bootc-style or Fedora CoreOS one-off VM images (T29,
deferred). T28 opened: secrets in published seeded images — proposed
burn-time SEED_DATA overlay or secret-free seeds. T22 sharpened: GHCR
implies GitHub as git home; internet = cold-start dependency to accept.
Still awaiting: T20 Tinkerbell ruling, T26 boundary ruling, step-3 deploy
mechanism dump.

## 2026-08-15 13:02 — T20 resolved: Tinkerbell dropped; iPXE rejected
Josh dropped Tinkerbell. Critical services now Zitadel, Vault, CAPI.
Bootstrap step 4 rewritten: lab01-03 get IncusOS via AMT-mounted seeded
ISOs + incus cluster join. T23 moot. iPXE follow-up answered and rejected:
upstream publishes no netboot artifacts (confirmed via Feb-2026 forum thread
asking exactly this), UEFI ISO-chainload flaky, SB key conflict; revisit
only if upstream ships netboot. Sneakernet: AMT covers lab01-03; pikvm01
mass-storage emulation may cover nas01 — MSD-through-kvm01 test added to
T01. Also earlier: T27 image-factory self-host requirements verified
(Helm chart, OCI cache registry, ECDSA signing key, cosign-verified Sidero
source pulls); awaiting Josh's adopt confirmation.

## 2026-08-18 14:16 — T26 resolved: product/instance working relationship
Josh ruled all four sub-decisions: (1) `GilmanLab/fleet` private sub-repo =
bare-metal-only instance config (IncusOS seeds + Incus/OpenTofu); k8s config
explicitly excluded — platform cluster + spawned clusters get separate repos
later (likely reusable-code repo + gitops repo, shape provisional). (2)
Pinned consumption, pre-release OK; lab is componere's first-class test bed;
capabilities often develop lab-first then get *promoted* into componere.
(3) incusos-builder nearly done — wait for it, no interim seed/burn tooling.
(4) Generic-product identity boundary confirmed ("would a second user want
this?" test). VISION.md Product-vs-instance section updated with the ruling;
T26 resolved; T30 opened (create fleet repo when first configs exist).
Outstanding rulings: T27 (factory adopt), T28 (seed secrets), step-3 deploy
mechanism dump. Consolidation into lab-v2-bootstrap.md + ADR-0002 nearing.

## 2026-08-18 14:19 — T27 resolved: self-hosted image-factory adopted
Talos image plane decided: self-hosted Sidero image-factory (bespoke builder
dead). New "Talos image plane" section in VISION.md: platform-service tier
on mgmt cluster (not critical-three); cold start via public factory.talos.dev
then repoint; generic images with CAPN-injected identity; cache-signing key
joins T15 custody; schematics live with cluster template (T08); stable URL
depends on DNS/ingress (open). T31 opened for the eventual deployment.
Remaining: T28 (seed secrets model), step-3 deploy mechanism dump; then
draft lab-v2-bootstrap.md + ADR-0002.

## 2026-08-18 14:25 — Leg 1 amended: no OCI publish for IncusOS images
Josh dropped OCI persistence for IncusOS images: publish→pull→burn round
trip adds work for a 4-node fleet; single-step local build+burn makes seed
injection (incl. secrets) trivial. Agreed — reproducibility lives in the
pinned recipe (config+checksum+tool version), not a persisted artifact.
T28 dissolved (nothing seeded is published; secrets Bitwarden→seed at burn,
nowhere at rest). VISION.md "OCI-backed distribution" renamed "Image
distribution"; leg 1 rewritten; kept: fleet CI validates seed rendering
without publishing. imgoci remains the format for leg 3 (bootc/CoreOS).
T25 note updated (no publish; local build+burn).
Remaining before bootstrap design draft: step-3 deploy mechanism dump.

## 2026-08-18 14:48 — VM orchestrator brainstorm (T32 opened)
Josh raised: what orchestrates Incus VMs — OpenTofu (original thought),
Crossplane, or other? Framed as two regimes: cattle-cluster VMs already
CAPI-owned (T09); the open question is pre-k8s VMs (3 mgmt Talos VMs +
one-offs). Crossplane rejected (runs in k8s — can't bootstrap; no first-
class Incus provider; duplicates CAPI). Real fork: (a) OpenTofu from laptop
(boring, zero new tools, mgmt cluster forever special) vs (b) CAPI self-
managed via kind+CAPN+clusterctl-move pivot (one source of truth, upgrades/
stretch as CAPI edits; choreography + CAPN maturity risk). Lean (b) spike-
verified; UM760 proposed as sacrificial Incus host for the spike. Rides
along: tofu state backend pre-lab (local encrypted → Garage later).
VM orchestration section added to VISION.md; T32 opened.

## 2026-08-18 14:52 — Non-Talos VMs decided: OpenTofu; T32 narrowed
Josh asked about non-Talos VMs. Decided: OpenTofu owns one-off (bootc/
CoreOS) VMs as resources in the same roots as Incus runtime config — CAPI
categorically wrong (cluster object model), no Incus VM operator exists,
plan/apply fits pets. Parked componere product idea: Incus VM-CR reconciler
(passes second-user test). T32 narrowed to mgmt-cluster Talos VMs only;
recorded honest caveat that tofu is in the stack regardless, so (b)'s value
is cluster-fleet consistency, not tool count; spike verdict now more
decisive between (a) and (b).

## 2026-08-18 16:21 — Secrets model corrected: SOPS repo, not Bitwarden
Josh: all non-generated secrets live in GilmanLab/secrets as a SOPS file
hierarchy; later automation (TODO) syncs to Vault; ephemeral/generated
secrets exempt from the mandate. Priority: create the repo now (not the
Vault sync). VISION.md: new Secrets section; Bitwarden references swept;
T15 superseded/resolved into T33 (create repo — must settle age
root-of-trust custody, hierarchy layout, and whether generated-durable
recovery secrets like ZFS recovery keys / seed client key / factory signing
key also live there — they need an out-of-lab, lab-independent home);
T34 = Vault sync, deferred. Awaiting Josh: age recipient decision, then
scaffold repo.

## 2026-08-18 16:38 — v1 "AWS" audit: iDrive e2 + age/YubiKey SOPS precedent
OldLabAwsAudit (full brief: history://OldLabAwsAudit) on ~/code/lab: NO
native AWS services anywhere — "AWS" = AWS SDK/Boto3 speaking S3 protocol
to iDrive e2 (image-pipeline intermediary: CI pushed Talos/VyOS/Harvester
images, Synology pulled; real AWS S3 explicitly rejected in v1 ADR-007).
v1 SOPS root of trust: age + YubiKey-PGP dual recipients, ONE key group
across all domains (e2 creds, talsecret, VyOS SSH) — blast-radius weakness;
CI age key as GitHub secret SOPS_AGE_KEY. Housekeeping hazard found:
plaintext IDRIVE_* keys in old ignored .env (vestigial).
Folded into VISION.md: Secrets precedent block; T33 sharpened (reuse YubiKey
PGP recipient?, fresh v2 age keys rec, per-subtree key groups rec); e2 added
as strong tofu state-backend candidate (rides-along note in VM
orchestration).
Awaiting Josh: recipient rulings for T33, and confirmation of what exactly
e2 continues to do in v2 (state backend? image intermediary is obsolete —
AMT delivery replaced NAS-pull).

## 2026-08-18 17:02 — Lineage corrected: glab is v1; KMS+PGP decided; AWS substrate
Josh corrected the migration source: ~/code/glab (not ~/code/lab) is the
deprecated predecessor. So: v0 = ~/code/lab (age+YubiKey, iDrive e2), v1 =
~/code/glab (full AWS substrate, GilmanLab/{infra,secrets,docs}), v2 = lab2.
Earlier OldLabAwsAudit examined v0 — conclusions lineage-corrected in
VISION.md.
Verified from glab: GilmanLab/secrets EXISTS with KMS-only SOPS
(alias/glab-sops, context Repo+Scope, scopes network-tailscale/network-vyos/
keycloak/talos-platform); GilmanLab/infra has aws/lab-foundation (VPC
172.16/16, KMS, Route53 glab.lol), aws/keycloak (EC2 id.glab.lol), OIDC
provider + token broker (legacy lambda destroyed), security/pki/root-ca
(alias/glab-pki-root-ca, pathlen:2); state bucket
glab-lab-tfstate-186067932323; account 186067932323 profile lab-admin.
Decided: secrets root of trust = AWS KMS + PGP (YubiKey recovery recipient =
conscious reversal of glab session-026 KMS-only rule; rationale AWS-loss
survivability, pending Josh confirm). Catalyst-infra pattern studied
(.sops.yaml Repo+Scope contexts, grant invariant, OIDC publisher roles).
Tofu state backend question dissolved: existing bucket is the answer;
e2 candidate withdrawn.
Tracker: T33 → restructure existing secrets repo; T35 AWS→GilmanLab/aws
migration (GlabAwsMigrationAudit spawned); T36 Keycloak vs Zitadel; T37
broader glab carry-forward audit. New AWS substrate section in VISION.md;
AWS accepted as hard external dependency alongside GitHub.

## 2026-08-18 17:05 — PGP reversal confirmed; T36 resolved: Zitadel
Josh confirmed PGP recovery recipient is intentional (AWS-loss recovery).
T36 resolved: Zitadel is v2 identity (he'd forgotten the hosted Keycloak);
keycloak root migrates into GilmanLab/aws as live infra with a follow-up
destroy once Zitadel serves. T35 scope confirmed: all four roots
(lab-foundation, keycloak, OIDC provider/token broker, pki root-ca).
VISION.md AWS substrate + tracker updated. Awaiting GlabAwsMigrationAudit
for the migration plan.

## 2026-08-18 17:11 — Migration audit distilled into T35 plan
GlabAwsMigrationAudit (full: history://GlabAwsMigrationAudit) found SIX
roots, not four: + aws/subnet-router (own root: EC2 router, EIP, IAM
glab-aws-subnet-router, dns-mirror via SSM; VyOS pulls glab.lol zone from
its Tailscale IP 100.80.89.100) and + network/tailscale (Tailscale provider;
state in OLD account bucket gilmanlab-tfstate/340752822076 via
jmgilman-prod — needs backend migration). github-token-broker root =
tombstone (targeted destroy in glab session 044; state likely retains only
the GitHub OIDC provider; never ordinary-apply; carve provider into small
identity root via cross-state mv/import). Keycloak root owns the CURRENT
broker Lambda (module v2.0.0). Migration mechanics: pure repo move, same
bucket/keys/locks, zero-diff plan acceptance; order freeze/capture →
bootstrap repo → tombstone resolve → foundation → root-ca → tailscale →
subnet-router → keycloak → ownership cutover. Risks: KMS identity, dual
root-ca.tfstate name in two buckets (never copy old), broker resurrection,
OIDC orphan consumers, DNS/route breakage, single-writer.
VISION.md AWS substrate rewritten with all six roots + plan; T35 ready to
execute pending Josh green-light + tailscale-root home ruling (aws vs
networking repo).

## 2026-08-18 17:15 — Tailscale root home resolved
Grounded network/tailscale contents: 2 AWS-coupled resources (federated
identity, VPC route approval — lifecycle-bound to subnet-router boot) + 2
non-AWS (MagicDNS, split DNS → lab CoreDNS). Ruling: whole root migrates
unchanged into GilmanLab/aws (keeps T35 zero-diff, single writer); optional
later split of the DNS resources into networking. T35 fully specified,
awaiting green-light.

## 2026-08-18 17:19 — AWS migration plan drafted for handoff
Wrote .journal/002/AWS_MIGRATION_PLAN.md: self-contained implementation
handoff (goal/non-goals, account/bucket facts, six-root inventory with
treatments, 9 invariants, phases 0-5: freeze/capture → repo bootstrap →
tombstone OIDC carve-out → pure moves foundation/root-ca/subnet-router/
keycloak → tailscale backend migration → cutover; per-root acceptance =
zero-diff plan; risks; open items left to implementer).
T35 → blocked/handed off: Josh will spawn a dedicated implementation
session; session 002 resumes tracking on its report (close T35, unblock
T33, open Keycloak-teardown task).

## 2026-08-18 18:05 — T35 closed: session 004 executed the migration
Verified via .journal/004/SUMMARY.md: six roots live in GilmanLab/aws
(aws/lab-foundation, aws/github-oidc [new, holds OIDC provider],
aws/subnet-router, aws/keycloak, network/tailscale, security/pki/root-ca);
all destination plans 0/0/0; identities preserved; tombstone resolved via
import + exact-instance removal (never applied); tailscale state pull/push
cross-account with lineage preserved; legacy writers removed (infra#57/58),
stale platform publisher workflow removed (platform#70), meta init.sh wired
(root#11, master 9fd7575 pulled). Correction absorbed: live Keycloak
instance is i-069f5e943c6e11092 (audit's cached ID stale).
Tracker: T35 resolved · T33 unblocked (next priority) · T38 opened
(Keycloak teardown, blocked on Zitadel serving) · T39 opened (timed
cleanup: shred /tmp/gilmanlab-aws-migration-20260819, delete old-account
tailscale state object after rollback window).

## 2026-08-18 18:09 — T33 plan drafted for handoff
Wrote .journal/002/SECRETS_RESTRUCTURE_PLAN.md. Inventory grounded from the
repo: 7 SOPS files across 4 scopes, plus stale tailnet policy + workflow
(superseded by session 003 / ADR-0002). Key design points encoded: KMS+PGP
in ONE key group (alternatives, not Shamir — PGP-alone must decrypt when
AWS is dead); existing file paths frozen (live consumers: keycloak labctl
boot, VyOS ansible, tailscale tofu root); new fleet scope + hierarchy
convention; generated-durable exception verbatim for README; ADR-0003
(KMS+PGP reversal) as meta-docs companion; CI decrypt = per-consumer OIDC
roles with the catalyst grant invariant, instantiated on first real
consumer only; phases with break-glass PGP-only decrypt proof and plaintext
hash acceptance. T33 → blocked/handed off.