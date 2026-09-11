# Phase 6 — Linux desktop image and `desktop.*` over exec

You are building the first desktop-capable image (`ubuntu/24.04/desktop`)
and the `desktop` capability root: Cua Driver running inside the guest,
invoked by `agentcompute` over Incus exec, screenshots pulled through the
file API and served over HTTP. This is the phase most likely to teach us
something that changes the vocabulary, so it is spike-first and the
spike's outcome is reported before the capabilities are finalized.

## Read first

1. Design draft: "Design Overview" desktop paragraph, the `desktop`
   table and the prose after it (Driver's vocabulary is the desktop
   vocabulary; `desktop.call` is a pass-through; no re-modeling), "A
   representative program" desktop lines, "Raw VNC" and "SPICE"
   alternatives, Open Questions still-open #2 and #3 and the resolved
   "screenshot return path" item (URL only, no base64).
2. `ARCHITECTURE_GO.md`: `internal/desktop/{driver,store}.go`, the
   `desktop.call` request flow (documented invocation is
   `cua-driver call <tool> <json> --screenshot-out-file <path>`), the
   screenshot store spec (transient disk, 128-bit random ids, 5-minute
   retention capped by sandbox expiry, 16 MiB/128 MiB bounds,
   `image.DecodeConfig`, GET/HEAD, `nosniff`, `no-store`, configured base
   URL, separate listener in stdio mode), risks (token continuity across
   one-shot CLI calls; URL reachability).
3. `IMAGE_PIPELINE.md` Linux section and `research/linux-images.md`
   (desktop recipe: `ubuntu-desktop-minimal`, GDM with Wayland disabled,
   `ubuntu-xorg` session auto-login for a dedicated user, Driver as a
   systemd *user* unit in that session, `tigervnc-scraping-server`
   `x0vncserver` mirroring the same display; pin a **non-prerelease**
   Driver asset + SHA-256; no curl-pipe installers).
4. Cua Driver docs: `https://cua.ai/docs/reference/cua-driver/cli-reference`
   (`call`, `--socket`, `--screenshot-out-file`, JSON on stdin),
   `mcp-tools-linux`, `platform-support` (X11 is the supported lane),
   `permission-modes`, `process-model` (on Linux `cua-driver serve`
   daemon + `cua-driver mcp/call --socket`), the Linux install script
   for the user-unit autostart pattern.
5. `PLAN.md` Phase 6 and Finding 7. Phase 2/4 reports (server, catalog,
   runner capacity numbers).

## The spike that comes first

Build the desktop VM image once (distrobuilder, VM, split output; see the
Linux report's recipe) and, with a throwaway Go program or shell in
`spikes/desktop/`, prove on a running instance in a disposable project:

1. `incus exec … -- cua-driver call list_apps '{}'` returns structured JSON
   for the auto-logged-in user's session (so the daemon is reachable from
   an exec that originates outside the graphical session — confirm which
   `--socket`/user the CLI needs).
2. `get_window_state` for a launched app (`launch_app` gnome-text-editor
   or similar) with `--screenshot-out-file /tmp/x.png`; then, in a
   **second, separate exec**, `click` by the returned `element_token`.
   Decision rule: if the token is accepted across invocations, the
   one-shot CLI model in the architecture stands. If it is rejected as
   stale/unknown, `desktop.call` must drive a long-lived
   `cua-driver serve --socket` per instance over an exec session that
   agentcompute keeps open; the vocabulary does not change — report this
   as the mechanism decision.
3. Pull `/tmp/x.png` through the Incus file API (binary, not the text
   `instance.file.read` path), decode it, note dimensions and bytes.
4. Restart the guest; confirm the daemon returns without intervention.
5. `x0vncserver` answers on the management network (Phase 5's default
   OVN network + a forward, or the Phase 2 bridge) so a human can look.

Record timings: exec round trip for a `call`, `get_window_state` with and
without the tree, screenshot size at default and `max_dimension` 1280.

## Deliverables

`agentcompute` PRs (image and server can be separate):

- `images/ubuntu-24.04-desktop/distrobuilder.yaml` + `files/` (GDM
  `custom.conf`, `~/.config/systemd/user/cua-driver.service`,
  `x0vncserver` unit, session defaults), pins, catalog entry (VM,
  `desktop: true`), publish workflow extended; boot-tested on the cluster
  (`$XDG_SESSION_TYPE=x11`, Driver daemon active, one `list_apps`).
- `internal/desktop/driver.go` (argv building — never a host shell string;
  bounded JSON buffer that fails rather than truncates; strip embedded
  image blocks; guest temp path selection and best-effort removal),
  `internal/desktop/store.go` + HTTP handler per the architecture,
  `internal/mcpserver/desktop.go` with `desktop.info`, `desktop.enable`,
  `desktop.call`, `desktop.screenshot` exactly as the draft's table.
  `desktop.info.tools` comes from the Driver (`cua-driver dump-docs` or
  the tool list the CLI exposes) at `enable`/first use, not hard-coded.
- `instance.create` waits for the Driver daemon on `desktop: true`
  images; `instance.wait(until="desktop")`.
- HTTP transport: screenshot handler mounted beside MCP; stdio mode
  starts the separate listener; `screenshots.base_url` required.
- Tests: `httptest` + scratch-dir store tests (expiry, sandbox purge,
  size bounds, GET/HEAD only); parser tests on captured Driver output
  from the pinned version; the integration lane gains one real
  `desktop.call` + screenshot fetch + decode.

## Working rules

- The Driver's tool catalog is not re-modeled as typed capabilities.
  Only if the spike shows agents fumbling JSON strings do you add typed
  conveniences, and then only for `get_window_state`, `click`,
  `type_text`, `press_key` — report it as a finding first.
- No base64 fallback. If the URL is unreachable from the agent host,
  that is a network finding, not a reason to change the contract.
- VNC is a fallback for humans and pre-login screens; it is not a
  transport agentcompute uses.
- Pin the Driver; record its version in `desktop.info`.
- Do not edit the design documents; report findings — particularly
  anything about token continuity, daemon/session wiring, and image
  sizes.

## Acceptance evidence

- The draft's representative program including the desktop lines runs via
  MCP: `client` on a private network only, `instance.wait(until="desktop")`,
  `desktop.screenshot` returns a URL, `desktop.call(tool="list_apps")`
  decodes; the agent host fetches the URL and gets a PNG.
- A real agent (your MCP client) performs: snapshot a window → click an
  element by token → snapshot again showing the changed state, all
  through `desktop.call`, in one `execute` program.
- Guest reboot → `desktop.info.ready` true again without operator action.
- `x0vncserver` reachable at the address `desktop.info.vnc` reports.
- Store behavior: an expired sandbox's screenshots 404 after the reaper
  runs; the 128 MiB cap rejects rather than evicts silently.
- Measured numbers in `images/README.md` and the report.
