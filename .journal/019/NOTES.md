---
id: 019
title: Design agentcompute, disposable compute for agents
started: 2026-09-11
---

## 2026-09-11 07:25 — Kickoff
Goal for the session: not yet stated; the user asked only to open a new session.
Current state of the world: meta repo `master` at `b62bc98` (5 behind origin). Four-node IncusOS cluster live (nas01 + lab01–03); storage converged. T48 (lab VLAN 30 datapath) remains blocked on the IncusOS stable release carrying lxc/incus-os#1306; nodes run `202608201218` with `auto_reboot: false`. Sessions 011, 012, 014–018 are still `in-progress` in `INDEX.md`. Latest closed session with a summary is 013 (2026-08-23).
Plan: wait for the user's actual request, then update the title and this log.

## 2026-09-11 07:54 — Goal stated; vocabulary draft written
Goal: initial design + planning docs for `agentcompute`, a lab-specific CodeMode MCP server giving agents disposable containers/VMs (Linux/Windows/macOS), desktops, and arbitrary network topologies. Josh: start with the agent vocabulary.
Inputs read: `~/code/meigma/codemode` (public-api, mcp-tools refs) and `~/code/meigma/template-mcp-codemode` README. Load-bearing CodeMode constraints: keyword-only flat scalar inputs (no lists/objects), 1 MiB value cap, default 5 s / 100 native calls per program, dotted names ≥2 segments.
Facts checked: Incus VGA console is SPICE-only (no Go client) → desktop I/O via in-guest VNC. VLAN 40 exists only on `gw01 eth2` (address plan) → sandbox VLAN to the cluster nodes is a real prerequisite (networking + fleet; first "instance VLAN" consumer).
Wrote `docs/docs/designs/drafts/agentcompute.md` on worktree `feat/agentcompute-design` (`e636c5d`), nav entry added, strict build passes. Vocabulary roots: `sandbox`, `image`, `instance`, `net`, `desktop`. Key provisional choices: sandbox = Incus project pinned to one member; management NIC on the sandbox VLAN by default; screenshots returned as HTTP URLs; blocking ops with raised CodeMode budgets; `router` image + `instance.exec` instead of routing vocabulary; macOS via Tart on an Apple Silicon host.
Open for Josh: the word `sandbox` (collides with `sandbox01`/`GilmanLab/sandbox`); which Mac hosts Tart; VLAN 40 vs new VLAN; reaching guests that opt out of the management NIC.
Note: session 018's only commit is "assess disposable desktop testing" (`.journal/018/NOTES.md`) — likely prior art; not read (protocol: other sessions' NOTES stay closed unless asked).
