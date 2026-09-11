# Phase 8 — macOS via Lume: the second backend

You are adding macOS guests to `agentcompute` through Lume on a dedicated
Apple Silicon host, and in doing so extracting the backend seam the
architecture deliberately deferred until a second implementation existed.
The macOS image is a host-local, operator-consented seed; it is never
published to a registry.

## Blocking prerequisite

**The Mac host must exist before the first VM/TCC experiment.** The
decision is a dedicated Apple Silicon machine in the lab (a Mac mini is
enough), not a personal workstation. If it is not racked, on the network,
and reachable over SSH, stop and say so. Everything before that point —
repo layout, pins, interface extraction plan — can be drafted, but do not
"spike" on a laptop and call it done.

## Read first

1. Design draft: macOS catalog row (Mac-local, operator-granted TCC,
   Screen Sharing fallback), "Backend mapping" Lume column (NAT-only;
   `net.*` errors; `lume ssh`/scp; `lume clone` snapshots; sidecar
   metadata), prerequisite 5, the Lume-vs-Tart alternative, "Where the
   server runs" (SSH key for the Mac host).
2. `ARCHITECTURE_GO.md`: "Decisions carried out of the review" (no seam
   until Lume; extract consumer-sized interfaces from real call sites),
   package layout `internal/lume/`, the Lume rows in state/concurrency
   (durable JSON sidecar on the Mac, atomic replace, enumerate real VMs,
   never delete by prefix alone).
3. `IMAGE_PIPELINE.md` macOS section and `research/macos-images.md` in
   full: pinned IPSW + `--unattended sequoia`, provision over `lume ssh`
   with a pinned Driver, **human TCC consent once** via `lume attach` +
   `cua-driver permissions grant` (no hand-editing `TCC.db`; Cua's own
   guidance), clone-smoke, two-guest ceiling, Lume 0.5.3 pulls by
   `name:tag` only, `lume serve` HTTP API on :7777, Apple SLA notes.
4. Lume docs: CLI reference, HTTP API reference
   (`https://cua.ai/docs/reference/lume/http-api`), limits, "how unattended
   setup works", SIP concept; Cua's macOS permissions reference and the
   Lume-VM Driver guide.
5. Phases 2/5/6 reports and the current `compute.Service` / `desktop`
   call sites — you are extracting interfaces from what those actually
   call, nothing more.
6. `PLAN.md` Phase 8, Finding 8.

## The spike that comes first (on the Mac)

1. Install pinned Lume (release asset + SHA-256 from `pins/lume.yaml`);
   `lume serve` as a launchd service; confirm the HTTP API answers from the
   agentcompute host (or the workstation) and that `lume ssh` works for a
   test VM.
2. `lume create seed-sequoia --ipsw <pinned> --unattended sequoia --cpu 4
   --memory 8GB --disk-size 100GB`; verify Setup Assistant is gone on
   first GUI boot (the Sequoia preset has a history of an Accessibility
   step — check).
3. Provision over `lume ssh`: pinned Driver (non-prerelease) installed so
   the daemon runs under `CuaDriver.app` in the Aqua session; Screen
   Sharing enabled for the fallback; no secrets left in the guest.
4. **Operator step**: `lume attach`, `cua-driver permissions grant`,
   approve Accessibility and Screen Recording, relaunch, prove
   `get_accessibility_tree` and `get_desktop_state` without prompts.
   Poll `permissions status --json` from the automation side.
5. Stop the seed. `lume clone seed-sequoia w1`; boot headless
   (`--display none`); prove SSH, `cua-driver call list_apps`, a
   semantic click by token, a screenshot pulled via scp, and that no new
   consent was needed. Delete the clone. Repeat the clone once more to
   confirm the seed is untouched.
6. Measure: create time, clone time, boot-to-ready, screenshot round trip
   via `lume ssh` + scp, disk usage per clone.

Decision rule: Lume is confirmed if clones boot, keep their TCC grants,
and the Driver works through exec-over-SSH without operator action, and
two concurrent clones run within the host's limits. If TCC grants do not
survive cloning, or NAT-only access blocks the server from reaching
guests via the Mac in an acceptable way, report **NOT CONFIRMED** with
the failing step; the documented alternative (Tart) is the owner's call,
not yours.

## Deliverables

Mac-side (kept in `agentcompute/images/macos/sequoia/desktop/`):
`image.yaml`, `unattended.yaml`, `provision.sh`, `verify.sh`, a runbook
`README.md` for the operator consent step, `pins/{lume,cua-driver,
sequoia-ipsw}.yaml`. A self-hosted runner on the Mac (`lume-builder`
label, concurrency 1) running a protected workflow that performs steps
1–3 and 5–6 and pauses for step 4 — or, if a paused workflow is more
trouble than it is worth, a documented manual procedure with `verify.sh`
as the gate. Say which and why.

Server-side (`agentcompute`):

- Extract consumer-sized interfaces from the existing call sites in
  `compute.Service` and `internal/desktop` — only the methods those
  call — and make `*incus.Client` satisfy them. Then `internal/lume/{client,
  sandbox,instance}.go` implementing the same methods over the Lume HTTP
  API + `lume ssh`/scp through the Mac host. No method the Incus path
  does not already need.
- `platform="mac"` on `sandbox.create` selects Lume; the sandbox is a
  name prefix `ac-<name>-` plus a JSON sidecar on the Mac (atomic
  temp-file replace) holding expiry/subject/instance mappings; the reaper
  scans the Mac too; `instance.create` = `lume clone` of the catalog seed
  + `lume run --detach --display none`; exec = `lume ssh`; files = scp;
  snapshots = clones of a stopped VM; `net.*` returns `AgentError`
  "unsupported on platform mac"; `instance.get.addresses` reports the NAT
  address Lume assigns.
- Catalog entry for `macos/sequoia/desktop` with `platform: mac` and a
  `seed:` name instead of a digest; `image.list(platform="mac")`.
- Tests: mocks of the extracted interfaces for the service; a Lume
  integration lane gated on `AGENTCOMPUTE_TEST_LUME`.

## Working rules

- Never push the seed to a registry. Never copy credentials into a guest.
- Two running macOS guests per host is Apple's ceiling; the reaper and
  `instance.create` must enforce it with a clear `AgentError`.
- Interface extraction is mechanical: if you find yourself adding a
  method "for Lume", that is a finding, not a change.
- Do not edit the design documents; report findings — notably TCC
  survival, NAT reachability, and anything about Lume's API that the
  backend mapping table got wrong.

## Acceptance evidence

- Spike transcript for steps 1–6 with timings.
- Via MCP: `sandbox.create(platform="mac")`, `instance.create(image=
  "macos/sequoia/desktop")`, `instance.exec("sw_vers")`, `desktop.call(
  "list_apps")`, `desktop.screenshot` URL fetched from the agent host,
  `instance.snapshot.create/restore`, `sandbox.delete` → `lume ls` shows
  only the seed. Server restart rediscovers a live Mac sandbox from the
  sidecar + `lume ls`. TTL expiry deletes it.
- `net.create` on a Mac sandbox → `capability failed: … unsupported on
  platform mac`.
- A third concurrent macOS instance is refused with a clear message.
- `go build ./...` shows Incus and Lume both satisfying the extracted
  interfaces with no Lume-only methods.

## Handoff from Phase 2 (2026-09-11)

The seam already exists: `compute.Backend` in `internal/compute/types.go`,
consumer-defined and slice-scoped (13 methods after slice 1, more after
Phases 5–6), with a mockery mock in `internal/compute/mocks`. Lume is a
second implementation of that interface in `internal/lume`, not an
extraction exercise. If Lume needs a method the Incus path does not
have, that is a finding to report, not a reason to widen the interface.
