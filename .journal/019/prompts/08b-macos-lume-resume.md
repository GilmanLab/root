# Phase 8 (resume) — Lume backend after the confirmed seed

You are resuming Phase 8 of agentcompute. The previous agent completed the
Mac-side spike and confirmed Lume, then stopped before the server-side
work. Read the original prompt (`prompts/08-macos-lume.md`) for the goal
and working rules, then this file for what changed. Where they disagree,
this file wins.

## State of the world (verified 2026-09-15)

**Host.** The Lume host is the lab's always-on **Mac Studio**, not a Mac
mini — design prerequisite 5 was amended by the owner. Everything runs
under a dedicated standard, hidden account `agentcompute` (uid 502): Lume
at `/usr/local/bin/lume{,.app}`, VM store in that account's home,
`lume serve` as a LaunchDaemon bound to **`127.0.0.1:7777` only**. The
host answers on `192.168.1.10` (en0) and `192.168.1.137` (en1) and on the
tailnet as `studio-1`. The server's SSH key is authorized for that
account only, **forced-command + forwarding-only** to `127.0.0.1:7777`
(`/usr/local/libexec/agentcompute-no-shell`, root-owned drop-in
`/etc/ssh/sshd_config.d/110-agentcompute.conf`). Proven: no shell, no
forward to :22 or :5900, no remote forwards. Do not weaken any of this;
if the backend needs something the tunnel cannot carry, that is a
finding.

**Seed.** `images/macos/tahoe/desktop/` in `agentcompute`
([agentcompute#29](https://github.com/GilmanLab/agentcompute/pull/29),
ready; check whether it merged). Train is **Tahoe 26.6.2 (25G83)**, not
Sequoia — the Sequoia recipe exists but is unqualified. Seed is 26.6 GB
on a 100 GB logical disk, kept stopped, never published. TCC grants
(Accessibility, Screen Recording, `com.trycua.driver`) **survive
cloning**; the Driver runs from a launchd agent exec'ing
`/Applications/CuaDriver.app/Contents/MacOS/cua-driver serve` (label
`com.trycua.cua_driver_daemon`) — `open -a` breaks the Driver's identity
gate. Display must be 1920×1200. Measured: clone 2–3 s, NAT address
10–11 s, ~26.5 GB per clone; `provision.sh` 6 s, `verify.sh` 6–7 s.

**Tailnet ACL.** [networking#21](https://github.com/GilmanLab/networking/pull/21)
(draft) restricts `studio-1:22` to `tag:agentcompute`. It depends on the
owner running `tailscale up --advertise-tags=tag:macbackend` on the
Studio first. Check whether both happened; if not, note it and continue —
it does not block the backend work.

**Design and architecture.** The design draft (worktree
`/Users/josh/code/lab2/.wt/feat-agentcompute-design/docs/docs/designs/drafts/agentcompute.md`,
branch `feat/agentcompute-design`) now records the Tahoe catalog row,
prerequisite 5 as amended, and the clone-wizard defect as open question
3. `ARCHITECTURE_GO.md` in the journal is unchanged for Lume: implement
`compute.Backend` (`internal/compute/types.go`, consumer-defined; count
the methods as they stand after Phases 5–6, not the 13 of slice 1) in
`internal/lume`. Do not edit either document, or anything under
`.journal/`; report findings.

## Findings from the spike you must design around

1. **Clones boot into Setup Assistant; the seed does not.** `killall
   "Setup Assistant"` logs the session out. The documented
   `com.apple.SetupAssistant DidSee*` keys do nothing on 26.6.2; Lume's
   `sequoia`/`tahoe` presets are byte-identical. **Diagnose this first, as
   an identity problem**: diff seed vs clone on Lume's `config.json`
   (`machineIdentifier`, `hardwareModel`, MAC), `ioreg -rd1 -c
   IOPlatformExpertDevice` inside each guest, and the SetupAssistant /
   loginwindow plists. If the identifier changes on clone, test a clone
   with the seed's identifier copied back — these guests are never signed
   into Apple services, so shared identity across concurrent clones costs
   nothing. If that removes the wizard, it becomes the clone step in
   `internal/lume` (clone → pin identity → run). Only if identity is not
   the trigger, fall back to a seed-side launchd agent that dismisses the
   assistant at login and report it as a residual. Either way `verify.sh
   --clone` must **fail** on a wizard, not skip the desktop check. A clone
   showing a wizard is not agent-facing.
2. **Lume's API accepts a third macOS guest and silently never starts
   it** (`202 pending`, VM stays `stopped`, only the daemon log says
   "exceeds the limit"). `instance.create` counts running macOS guests on
   the host itself and refuses the third with a clear `AgentError`; the
   reaper uses the same count. The owner's own macOS VMs share the budget
   — say so in the error text.
3. **`lume ssh` is not argv-safe** (joins argv with spaces; the guest
   re-parses). Exec goes over direct `ssh` to the guest's NAT address via
   the host, with the same two capped writers and truncation flags as the
   Incus path. Files go over `scp`/`sftp` the same way.
4. **`lume run --detach` needs a controlling terminal.** Start and stop
   VMs through the HTTP API only.
5. **Per-VM VNC listens on `*:port`** (LAN-reachable, generated
   password) while the API is loopback-only. Add a `pf` anchor on the
   Studio restricting Lume's VNC range to loopback and the tailnet,
   applied by the runbook, and file an upstream Lume issue asking for a
   VNC bind address. In-guest Screen Sharing cannot be enabled on macOS
   26; Lume's `vncUrl` is the fallback console.
6. **`cua-driver status | head` panics on broken pipe** — don't pipe it.

## Deliverables (server side; Mac side is done unless finding 1 changes it)

- `internal/lume/`: `compute.Backend` over the Lume HTTP API through the
  SSH tunnel plus direct `ssh`/`scp` to guest NAT addresses. The previous
  agent's mapping was 24 methods map, 10 refuse (`net.*`, anything
  cluster-only) with `AgentError "unsupported on platform mac"`, 2
  synthetic (address reads from Lume's NAT lease). Sandbox = name prefix
  `ac-<name>-` plus a JSON sidecar on the Mac (atomic temp-file replace)
  holding expiry, subject, instance mappings; the reaper scans the Mac;
  enumerate real VMs, never delete by prefix alone.
- Platform dispatch: `sandbox.create(platform="mac")` selects Lume;
  `image.list(platform="mac")`; catalog entry `macos/tahoe/desktop` with
  `platform: mac` and `seed:` instead of a digest.
- The guest-count gate (finding 2) and the identity-pinning clone step
  (finding 1, if confirmed).
- Tests: mockery mocks of `compute.Backend` for the service paths; a Lume
  integration lane gated on `AGENTCOMPUTE_TEST_LUME` that runs against the
  Studio.
- Runbook additions in `images/macos/README.md`: pf anchor, identity
  pinning, the guest-count rule.
- Upstream: Lume issues for the silent third-guest accept, `lume ssh`
  argv handling, VNC bind address. Hand the issue bodies to the owner in
  your report if the project's submission policy rejects CLI-filed issues.

## Acceptance evidence

- Via MCP against the deployed service: `sandbox.create(platform="mac")`,
  `instance.create(image="macos/tahoe/desktop")` → Running with **no
  wizard on the console** (screenshot via `desktop.screenshot` shows a
  desktop, not Setup Assistant), `instance.exec("sw_vers")`,
  `desktop.call("list_apps")`, `desktop.screenshot` URL fetched from the
  agent host, `instance.snapshot.create/restore`, `sandbox.delete` →
  `lume ls` shows only the seed.
- Server restart rediscovers a live Mac sandbox from the sidecar +
  `lume ls`; TTL expiry deletes it.
- `net.create` on a Mac sandbox → `capability failed: … unsupported on
  platform mac`.
- A third concurrent macOS instance is refused before any API call, with
  the clear message; two concurrent instances both run.
- From the agentcompute VM: the SSH key reaches `127.0.0.1:7777` and
  nothing else (re-prove the negatives after your changes).
- `go build ./...` with Incus and Lume both satisfying `compute.Backend`;
  no Lume-only methods on the interface.
- Measured: `instance.create` wall time for a Mac guest end to end, and
  screenshot round trip through the service.

Report with findings, including the finding-1 diagnosis and its evidence,
and the disposition of every PR you open. Do not edit the design
documents or anything under `.journal/`.
