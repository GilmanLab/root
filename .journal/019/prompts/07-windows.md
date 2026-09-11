# Phase 7 — Windows images, `net.impair`, and router helpers

Two independent tracks: (a) `windows/11/desktop` and `windows/server-2025`
as cluster-local Incus images, baked on the cluster and never published to
a registry; (b) the `router` image's `/opt/router/` helpers and the
`net.impair` capability exercised in a real topology. Run them in parallel
if you have the capacity; they share no files except the catalog.

## Read first

1. Design draft: image catalog rows for Windows (cluster-local, Cua Driver
   at logon, VNC fallback, Server Core), the `net.impair` row and the
   "OVN covers the floor" paragraph (routing/exotic NAT/impairment are
   `instance.exec` against a `router` instance; the image is the
   extension point), "Backend mapping", Validation bullet on Windows
   screenshot latency.
2. `IMAGE_PIPELINE.md` Windows section and `research/windows-images.md`
   in full — repack, unattended install, Sysprep, capture, the
   interactive-session requirement for the Driver, VNC choice (UltraVNC;
   TigerVNC's `winvnc` is unmaintained), BitLocker/vTPM caveats, licensing.
3. `ARCHITECTURE_GO.md` "Core types" (`ExecRequest.Argv` per guest OS:
   `cmd.exe /c` for Windows), `net.impair` note (validated `tc` args via
   exec).
4. distrobuilder `repack-windows` docs and source (`main_repack-windows.go`,
   `windows/drivers.go`); Incus docs for VM ISO boot, `security.secureboot`,
   TPM device, the agent CD (`agent:config` — must stay attached in the
   runtime profile); Microsoft's unattend reference (`FirstLogonCommands`
   run concurrently), Sysprep options (`/generalize /oobe /mode:vm
   /shutdown /quiet`); Cua's Windows session guide (Session 0 vs
   interactive session, `cua-driver autostart enable`).
5. Phase 6's report (Driver invocation mechanism, token continuity) and
   Phase 5's (OVN default network, forwards). `PLAN.md` Phase 7, Finding 8.

## Licensing gate (read before doing anything Windows)

Evaluation ISOs grant test rights; they do not grant redistribution, and
they expire. The decision already taken: Windows images are **cluster-local
Incus aliases, never pushed to GHCR**. Ask the owner which media you are
allowed to use (evaluation vs licensed) before downloading anything; do
not proceed on an assumption. Record product/edition/build and the
official ISO SHA-256 in `images/windows/pins.lock.yaml`.

## Track A — Windows

Spike first, in a disposable project on one member:

1. Repack the ISO with distrobuilder (`--drivers` pointing at a pinned
   virtio-win ISO + SHA; `--windows-version w11` / `2k25`). Repack needs
   root and scratch, not KVM; do it on the publisher runner or `sandbox01`.
2. Empty VM on the cluster: `security.secureboot=true`, TPM device
   (Win11), the repacked ISO, a tiny payload ISO carrying
   `Autounattend.xml` + `bootstrap.ps1`, the agent CD. One
   `FirstLogonCommands` entry. Server 2025 selects Server Core.
3. Win11: create the automation user, arrange interactive console
   auto-logon, install the pinned Driver as that user, `cua-driver
   autostart enable` from the interactive session; UltraVNC as a boot
   service listening only on the sandbox network. Server Core: Incus
   agent + pinned servicing only.
4. Confirm `manage-bde -status` fully decrypted; remove media and
   caches (Microsoft: cached answer files can retain secrets); Sysprep
   with `deploy-unattend.xml`; never boot the golden source again.
5. `incus publish` → alias `windows/11/desktop-<build>` in the
   `image-build` project (or the shared images namespace the catalog
   reconciler reads — decide with Phase 2's reconciler in mind); launch a
   fresh clone with the runtime profile (agent CD + TPM + Secure Boot):
   fresh SID/hostname, `incus exec` works, Driver daemon in Session 1+,
   one `list_windows` and a screenshot through `desktop.call`, VNC at the
   login screen. Delete the clone.

Decision rule: the fresh-clone GUI call is the promotion gate. If the
Driver's interactive scheduled task does not survive Sysprep, make the
deploy answer file's first-logon bootstrap recreate it idempotently and
retest; report whichever worked.

Deliverables: `images/windows/{pins.lock.yaml, common/{instance.yaml,
bootstrap.ps1, finalize.ps1, smoke.ps1}, windows-11-desktop/{Autounattend.xml,
deploy-unattend.xml, ultravnc.inf}, windows-server-2025/{…}}`;
`.github/workflows/windows-images.yml` orchestrating the bake on the
cluster from the publisher runner (no nested virt; the runner only talks to
the Incus API); catalog entries with `alias:` instead of a digest and the
catalog reconciler accepting alias-only entries; `ExecRequest` argv for
Windows guests; `desktop.*` paths verified on Windows (file API pull of
the screenshot, temp path conventions on `C:\`).

## Track B — router helpers and `net.impair`

- `images/router/files/opt/router/`: a small, reviewed set of helpers
  that recurring topologies need — start with `nat` (modes: `masquerade`,
  `port-restricted`; args `--inside`, `--outside`), `route` (static
  routes), `dhcp` (dnsmasq on an interface with a range), and `wg`
  (WireGuard endpoint). Shell or Python, no daemons beyond the tools
  themselves, each with `--help` and idempotent re-runs. These are the
  "helper scripts baked into the image before they become vocabulary"
  the design describes; do not add vocabulary.
- `net.impair` in `agentcompute`: builds validated `tc qdisc … netem`
  arguments (latency/jitter/loss/rate, `clear`) and runs them via exec on
  a Linux guest's named NIC; `AgentError` on non-Linux guests or unknown
  NIC.
- Exercise the draft's representative program **exactly as written**
  (port-restricted NAT via `/opt/router/nat`) plus `net.impair` on the
  router's `wan` NIC: measure a client `ping` before/after 100 ms
  latency + 5% loss, then `clear`.
- Restricted-project check: the router container runs unprivileged under
  the sandbox project restrictions; document which capabilities
  (`CAP_NET_ADMIN` inside the container) it needs and that they are
  available without `security.privileged`.

## Working rules

- No registry publication of Windows artifacts; no Windows media in git.
- Serialize Windows bakes (capture/compression is I/O heavy on the
  cluster's `data` pool).
- Do not edit the design documents; report findings — especially the
  Sysprep/autostart result, capture latency, image sizes, and anything
  about Windows exec semantics (`cmd.exe` vs PowerShell, exit codes,
  output encoding) that the `instance.exec` contract should state.

## Acceptance evidence

- Fresh Win11 clone: `incus exec … -- cmd.exe /c ver`, `desktop.call
  list_windows` returning windows from Session 1+, a `desktop.screenshot`
  URL producing a PNG within 2 s of `desktop.info.ready`, VNC answering
  at the login screen. Server Core clone: exec works, no Desktop
  Experience.
- `manage-bde -status` output from the golden source before capture.
- Catalog reconciler accepts the alias entries; `image.list` shows both
  Windows images with `platform: incus`, `desktop` true/false correctly.
- Representative program transcript with `/opt/router/nat --mode
  port-restricted`, WAN-side capture (`tcpdump` on the router) showing
  the translated source, and the `net.impair` before/after/clear ping
  numbers.
- Measured: install-to-capture wall time, image sizes, clone boot-to-ready.
