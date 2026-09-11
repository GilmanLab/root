# agentcompute image pipeline: research synthesis

Session 019, 2026-09-11. Synthesized from three researcher reports
(`agent://LinuxImages`, `agent://WindowsImages`, `agent://MacImages`) plus
my own reading of `meigma/incus-gh-runner` and the imgoci/componere repos.
Suggestions, not decisions.

## The shape that falls out

Every image family splits into two kinds of work, and the split decides
where CI runs:

| Kind | Needs | Examples |
| --- | --- | --- |
| **Assemble** — build a rootfs/disk without booting it | root + loop devices on Linux; no KVM | distrobuilder for `router` and `ubuntu/24.04/desktop`; `repack-windows` ISO injection |
| **Bake** — boot a VM, provision it, capture it | KVM (or Apple Virtualization) | Windows unattended install + Sysprep; macOS Lume seed; every boot-test |

Assemble work fits an ephemeral runner VM. Bake work does not fit *inside*
a runner VM as `incus-gh-runner` ships it (`security.nesting=false` by
policy), and does not fit GitHub-hosted runners (14 GB disk, no reliable
KVM, no nested virt on arm64 Macs). Bake work belongs on the hypervisor
itself: the CI job is an **orchestrator** that drives the cluster's Incus
API (or a Mac's `lume serve`) with scoped credentials, in a dedicated
`image-build` project, and never needs nested virtualization.

That is the whole recommendation in one line: **runners assemble;
the lab bakes; CI orchestrates; GHCR stores; a reconciler imports.**

## Per family

### Linux (`router`, `ubuntu/24.04/desktop`) — distrobuilder

- distrobuilder 3.3.1 (Apache-2.0, Incus's own tool, active). YAML recipe
  → `unified.tar.xz` (container) or `incus.tar.xz` + `disk.qcow2` (VM).
  Builds VMs via loop devices + `qemu-img`; **no KVM**. Needs root.
- Pins: Ubuntu Snapshot Service timestamp (`APT::Snapshot`), Alpine
  package constraints, distrobuilder release SHA, Cua Driver release asset
  SHA (0.28.0 is a *prerelease* — pick and record an approved version),
  fixed creation timestamp for near-reproducible output.
- Desktop recipe: `ubuntu-desktop-minimal`, GDM with Wayland disabled and
  `ubuntu-xorg` session auto-login for a dedicated user, Cua Driver as a
  systemd *user* unit in that session, `tigervnc-scraping-server`
  (`x0vncserver`) so VNC mirrors the same display. No canonical
  Ubuntu+Cua recipe exists upstream; the first real boot-test is the
  release gate.
- Rejected: Packer (BUSL + stale community Incus plugin), bootc/osbuild
  (no supported Ubuntu bootc base; Fedora-centric), mkosi (great for
  IncusOS, emits no Incus metadata/qcow2 pair), Incus `oci:` remote (app
  containers, not system containers), cloud-init-at-launch (not
  immutable).

### Windows (`windows/11/desktop`, `windows/server-2025`) — repack + bake on cluster

- distrobuilder `repack-windows` injects **pinned** virtio drivers into a
  Microsoft ISO (pass `--drivers`; the default fetches a moving
  `latest-virtio`). Output is still an ISO.
- Bake on the cluster: empty VM in `image-build` project on a designated
  member, `security.secureboot=true`, TPM device for Win11, attach
  repacked ISO + a tiny `Autounattend.xml` payload ISO + the Incus agent
  CD (`agent:config`, must stay attached in the runtime profile). One
  `FirstLogonCommands` → `bootstrap.ps1`. Server 2025 = Server Core.
- Cua Driver must run in the *interactive* session: install as the
  automation user, `cua-driver autostart enable` from that session
  (Session 0 sees no windows). VNC fallback: UltraVNC as a boot service
  (TigerVNC's `winvnc` is declared unmaintained). Whether the Cua
  scheduled task survives Sysprep is **unverified** → fresh-clone GUI call
  is a hard gate.
- `Sysprep /generalize /oobe /mode:vm /shutdown /quiet`, never boot the
  golden source again, `incus publish` → `incus image export --vm` →
  split metadata + qcow2. Confirm BitLocker is fully decrypted before
  capture (24H2 auto-encrypts; the vTPM is per-VM).
- **Licensing is release-blocking**: eval ISOs give test rights, not
  redistribution; private GHCR only, and only after the license owner
  says so. Eval images expire, so they are not a durable catalog.

### macOS (`macos/sequoia/desktop`) — Lume seed on a bare-metal Mac

- `lume create --ipsw <pinned> --unattended sequoia` → provision over
  `lume ssh` with the pinned Driver → **human TCC consent once** via
  `lume attach` + `cua-driver permissions grant` (no supported MDM-less
  unattended path; Cua says don't hand-edit `TCC.db` for reusable seeds)
  → clone-smoke → stop.
- The consented seed stays **host-local** by default (Cua's own guidance;
  Apple SLA permits two VMs per Mac for dev/test and does not bless
  registry redistribution). `lume push` to private GHCR only with legal
  sign-off; and Lume 0.5.3 pulls by `name:tag` only — digest pinning is a
  preflight `HEAD` compare, not a pull-by-digest (upstream gap).
- GitHub-hosted macOS runners cannot do any of this (M1, 7 GB, 14 GB, no
  nested virt). The Mac is a self-hosted runner with label `lume-builder`,
  concurrency 1.
- `ghcr.io/trycua/macos-sequoia-cua:15.3` exists but its contents (Driver
  version, TCC state) are undocumented; don't assume it satisfies the
  design.
- Honest status: macOS is *semi*-GitOps. Recipe, pins, and verification
  are in git; the seed is a stateful artifact produced with one manual
  step.

## Publication and the last mile

- **Publish** Incus images as imgoci releases to GHCR: `target=incus`,
  `representation=incus-vm`, roles `metadata` + `disk`; BigOCI for the
  big disks (GHCR: 10 GB/layer, 10 min/upload → keep chunking). imgoci
  has no `incus-container` representation yet — settle one before
  publishing `router` (spec allows extension values). Attest the
  release-index digest (same pattern as the runner-image guide).
- **Incus does not read imgoci.** Something must resolve the digest,
  fetch + verify roles, `incus image import ... --alias`, smoke-launch,
  then move the stable alias. Two ways to own that:
  1. *Now:* agentcompute's catalog entries carry `ref@digest`; at startup
     (and on catalog change) it reconciles cluster aliases to the
     catalog using `imgoci/go` + the Incus client. Small, no new
     service. Pre-warm at startup so first `instance.create` isn't a
     20 GB pull.
  2. *Later, product-correct:* `imgoci/simplestreams-oci` (today a bare
     template) serves a simplestreams index backed by GHCR; the cluster
     adds it as a native remote and caches images itself. This is that
     project's first real consumer.
- The catalog file in git is the GitOps root: PR updates the digest, the
  reconciler makes the cluster match.

## CI on the lab: `incus-gh-runner`

Yes, but two facts shape it:

1. **Unix socket only** (`internal/adapters/incus/client.go`:
   `ConnectIncusUnixWithContext`). It cannot target the IncusOS cluster
   over HTTPS today. Options: run it on `sandbox01` (local Incus, Ubuntu,
   UM760 32 GB — fine for 1–2 runner VMs; loosely meets the "dedicated
   host" advice), or add an HTTPS + client-cert connection mode to the
   controller. The feature passes the second-user test (IncusOS users,
   anyone with remote Incus) and would let the controller run as a VM on
   the cluster where the capacity is (3× 64 GB MS-02s), or on the
   `ovh-incusos` box.
2. **Runner VMs have `security.nesting=false`** by hardened baseline. Good
   — it means the design above never asks for nested virt. Runners do
   assemble work (distrobuilder needs root + loop devices: a *publisher*
   runner image with narrowly scoped sudo, restricted to protected refs,
   separate from the general untrusted-PR pool) and orchestrate bake work
   through the Incus API with a scoped client cert for the `image-build`
   project.

Bootstrapping: the runner VM image itself is the pipeline's first
customer — a minimal Ubuntu server distrobuilder recipe implementing the
guest contract. First build runs on a GitHub-hosted runner (fits 14 GB
for a server image) or locally; thereafter the lab builds its own.

Unknowns to measure on the first three builds: wall time, peak RSS,
scratch high-water mark, artifact sizes. Nobody publishes numbers for
these exact images. Planning reservations: router 4 vCPU/8 GiB/30 GiB;
desktop 8 vCPU/16 GiB/120 GiB; Windows bake VM 4 vCPU/8 GiB/100 GiB;
macOS seed job 6 h timeout.

## Suggested order

1. `images/` tree in the `agentcompute` repo: `pins.yaml`, one dir per
   image, `catalog.yaml` with `ref@digest`.
2. distrobuilder `router` recipe, built on a GitHub-hosted runner, boot-
   tested via the cluster API, published as imgoci → proves publish +
   reconcile end to end with the smallest artifact.
3. Runner VM image via the same path; stand up `incus-gh-runner` on
   `sandbox01`; move builds there.
4. Linux desktop recipe (the first Cua-in-guest acceptance).
5. Windows bake-on-cluster (after the licensing answer).
6. macOS seed on the Mac (after the "which Mac" answer).

Candidate upstream work surfaced: `incus-gh-runner` remote-HTTPS
connection mode; imgoci `incus-container` representation;
`simplestreams-oci` as the native last mile; Lume pull-by-digest.
