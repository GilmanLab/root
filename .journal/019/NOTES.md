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

## 2026-09-11 08:03 — Lume and Cua Driver adopted into the draft
Josh asked: lume over tart? Cua for computer use? Researched cua.ai docs (Lume 0.5.3 CLI ref, Cua Driver platform support + integration model + MCP tool catalog, Sandbox SDK runtime support 0.4.3) and trycua/cua issues.
Facts: Lume = MIT, `lume serve` HTTP API :7777, VNC built in, OCI images, NAT-only networking (cua#1007 open, NAT bug cua#483). Tart = Fair Source, CLI only, bridged/softnet, Packer plugin. Cua Driver = Rust in-guest runtime, 56 MCP tools (AX tree + element tokens, pixel fallback, screenshots, CDP browser), every tool also one-shot CLI `cua-driver <tool> '<json>'` with `--screenshot-out-file`; transports are stdio / local socket only. Cua Sandbox SDK = Python, runtimes QEMU/Docker/Hyper-V/Lume/Android, no Incus, snapshots not implemented.
Decisions (provisional, in draft `7c4bc0d`): Lume replaces Tart; Cua Driver over `instance.exec` replaces raw VNC as the primary desktop path (VNC = fallback). `desktop.*` collapses to `info`, `enable`, `call(tool, args_json)`, `screenshot`. Big win: desktop work needs no guest network reachability, so former Open Question 2 (guests with `management=False`) is dissolved. Rejected: Cua Sandbox/Fleets as substrate (listed as buy alternative). New open questions: Driver-in-image recipe details/TCC on macOS; `desktop.call` JSON-string ergonomics.
Observation: the omp harness `computer` prelude (ax refs, background delivery, BackgroundUnavailable) is cua-driver-shaped, so agents will find the guest desktop model familiar.
