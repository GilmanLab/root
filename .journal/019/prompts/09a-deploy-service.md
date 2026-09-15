# Phase 9a — Deploy `agentcompute` as a cluster HTTP service

This is the first half of `prompts/09-deploy.md`: make the service exist.
The second half (promote the design draft, ADRs, runbook validation with
nothing but `search_api`) is Phase 9b and waits for Phases 7 and 8. Read
`09-deploy.md` for context; this file narrows it and overrides three
things: TLS, the tailnet identity, and what "done" means.

Why now: Phase 8's Lume backend is implemented but its live acceptance
needs a deployed server — specifically the server's tailnet identity, so
the Mac host's SSH key can be source-pinned to it and the tailnet ACL
([networking#21](https://github.com/GilmanLab/networking/pull/21), which
allows `tag:agentcompute` → `studio-1:22`) applies. No such node exists
yet; `sandbox01` is not it.

## Read first

1. `09-deploy.md` items 1–5 (design draft "Where the server runs",
   `ARCHITECTURE_GO.md` configuration and deployment, Phase 2/5/6 reports,
   fleet's OpenTofu conventions for one-off VMs — `incus/incus-gh-runner/`
   from Phase 4 is the template to copy, and Phase 5's `ovncentral01`
   root for the VLAN 10 attachment).
2. Phase 4's report for how a fleet-owned VM gets credentials (systemd
   credential drop-ins, SOPS escrow) and Phase 8's runbook
   (`images/macos/README.md`) for the Mac SSH key shape: the server holds
   a key for the `agentcompute` account on the Studio, source-pinned to
   this VM's tailnet address.
3. The networking repo's Tailscale policy (`tag:agentcompute` is already
   defined or drafted in #21 — confirm) and how tagged nodes are enrolled
   in this lab (the OAuth/auth-key convention used for `sandbox01` and the
   runner controller; check `GilmanLab/secrets` and networking's
   README/runbooks).

## Deliverables

Infrastructure (fleet, one OpenTofu root `incus/agentcompute/`):

- VM `agentcompute01` on **lab01, lab02, or lab03** — not `nas01`, which
  already carries `ovncentral01` and `ghrunner01`. Attached to VLAN 10
  (Incus API at `https://10.10.10.14:8443`, pinned cluster cert) and VLAN
  40 (reaching guests, forwards, screenshot URLs). Ubuntu 24.04, sized
  per `ARCHITECTURE_GO.md`.
- Tailscale node with `--advertise-tags=tag:agentcompute`, enrolled with
  the lab's existing tagged-node mechanism, so the node is
  `agentcompute01` on MagicDNS and the ACL in #21 covers it.
- **TLS via Tailscale**: `tailscale serve` terminates HTTPS with a public
  Let's Encrypt certificate for `agentcompute01.<tailnet>.ts.net` and
  proxies to the service's local HTTP listener. This is the ADR-0005
  sanctioned path for browser/harness-trusted names (public ACME); there
  is no internal issuer yet and the service must not wait for one. The
  service listener binds loopback (or the tailnet address) only; nothing
  on VLAN 40 exposes the MCP endpoint. `screenshots.base_url` is the
  `ts.net` name.
- Credentials as systemd credentials, never in config or git plaintext:
  Incus client cert restricted to creating `ac-*` projects plus reading
  the images it needs (Phase 2/5 defined the identity; reuse it), the Mac
  SSH key, the bearer token(s). All escrowed in `GilmanLab/secrets` under
  the service's scope.
- `agentcompute01.glab.lol` via the lab's existing DNS mechanism if the
  address plan has a convention for service names; otherwise the `ts.net`
  name is the name and say so.

Software (`agentcompute`):

- First tagged release through the template's Release Please + GoReleaser
  + attestation path; the fleet root pins the release by version and
  digest.
- HTTP auth: replace the demo verifier with static bearer tokens read
  from a systemd credential — one token per agent identity, the token's
  name recorded as `user.agentcompute.subject` on sandboxes as designed.
  Boring on purpose; tailnet-identity or OIDC auth is a later ADR if ever
  needed.
- The reaper runs continuously under the service (TTL promise true from
  the deployment, not from a workstation).
- Nothing else new. A missing or broken capability is a gap in an earlier
  phase: fix it in its own PR and note it.

## Acceptance evidence

- `tofu plan` clean after apply; the VM is `RUNNING` on its member and
  visible as `agentcompute01` in `tailscale status` with `tag:agentcompute`.
- From a workstation on the tailnet: `curl https://agentcompute01.<tailnet>.ts.net/…`
  with the bearer token reaches the MCP endpoint; without it, 401; the
  certificate chains to a public root.
- `search_api` over MCP from an agent harness on the tailnet returns the
  vocabulary; one Linux sandbox lifecycle end to end (`sandbox.create` →
  `instance.create` → `instance.exec` → `desktop.screenshot` URL fetched
  from the harness → `sandbox.delete`) with `user.agentcompute.subject`
  set to the token name.
- Service restart rediscovers live sandboxes; a sandbox with a 5-minute
  TTL is gone within one reaper interval after expiry.
- From `agentcompute01`: `ssh agentcompute@studio-1` succeeds (once the
  Phase 8 agent has installed the source-pinned key), and the same key
  from `sandbox01` or a workstation is refused.
- Report the VM's tailnet IPv4 and MagicDNS name prominently — the Phase
  8 agent needs them.

Report with findings; do not edit the design documents or anything under
`.journal/`.
