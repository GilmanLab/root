# Phase 2 (resume) — Go slice 1 after the network spike stop

You are resuming Phase 2 of agentcompute. The previous attempt correctly
stopped at the project/bridge spike (draft PR
[GilmanLab/agentcompute#14](https://github.com/GilmanLab/agentcompute/pull/14),
branch `feat/go-slice1`, worktree `agentcompute/.wt/feat-go-slice1`,
evidence in `spikes/project-bridge/probe.py`, `spikes/agent-error/main.go`,
`spikes/results.json`). Two Incus facts contradicted the architecture as
written; the architecture has been corrected and the decisions below are
made. Re-read the original Phase 2 prompt
(`prompts/02-go-slice-1.md`) — everything in it still applies except
where this file overrides it — and the corrected
`/Users/josh/code/lab2/.wt/journal-jmgilman/.journal/019/ARCHITECTURE_GO.md`,
section "State and concurrency", paragraph "Default network, slice 1
(corrected after the Phase 2 spike)".

## Decisions (not up for re-litigation in this phase)

1. **Managed bridges are defined on every member.** That is Incus's only
   cluster model: define with `--target` on each member, then activate.
   Each member's copy is its own L2 domain with its own dnsmasq/NAT — the
   `kind="bridge"` semantics the draft already documents. A bridge-backed
   sandbox therefore keeps all its instances on one member
   (`user.agentcompute.host`; slice 1: the configured member), and
   `instance.create(host?)` on a bridge sandbox must equal that member or
   return an `AgentError`.
2. **Incus bridge names are opaque short IDs**: `ac` + 8 random lowercase
   hex (10 characters, inside the 15-character interface-name limit),
   random rather than derived from the sandbox name, collision retried.
   Network config carries `user.agentcompute.sandbox=<sandbox>`,
   `user.agentcompute.name=<agent-facing name>` (`default`, `lan`, …),
   `user.agentcompute.version=1`. Agent-facing names resolve to Incus
   names through metadata only; `restricted.networks.access` lists the
   Incus names; the reaper finds bridges by metadata. No prefix parsing,
   no truncation, no hashing of the agent-facing name.
3. Everything else in the original prompt stands: `features.networks=false`
   sandbox projects, dependency-ordered deletion (now including "delete
   the bridge — which removes it from all members — after instances"),
   `AgentError` (already proven), catalog reconciliation accepting both
   reference forms, restricted-cert tests asserting filtered reads.

## Re-run the spike, then build

Re-run `spikes/project-bridge/probe.py` under the corrected mapping and
extend it to what the first run never reached:

- Two sandboxes `ac-a`, `ac-b`; bridges `ac<hex>` defined on all four
  members and activated; `restricted.networks.access` per project.
- `router` launched in each on the configured member with a NIC on its
  own bridge: NAT egress works (`wget -qO- https://1.1.1.1` or a ping to
  `10.10.40.1`); `ac-a` attaching to `ac-b`'s bridge is refused.
- Cross-member sanity: launch one instance of `ac-a` on a *different*
  member (temporarily bypassing the placement rule in the probe) and
  show it cannot reach the first — record this as the reason for the
  placement rule, then delete it.
- Full teardown; `incus network list` and `incus project list` filtered
  to the spike's names are empty on every member.

Then implement slice 1 exactly per the original prompt, reusing the
draft PR's branch (rebase onto `master` if needed). Keep the spikes'
reproductions and `spikes/results.json` updated with the second run;
delete `spikes/images` once its logic is absorbed into the reconciler.

## Acceptance evidence

All bullets from the original prompt's "Acceptance evidence" section,
plus:

- `net.create(sandbox=…, name="lan", kind="bridge")` returns
  `{name: "lan", kind: "bridge", …}` while `incus network list` shows an
  `ac<hex>` bridge with `user.agentcompute.name=lan` on every member.
- `instance.create(host="<other member>")` on a bridge sandbox returns
  `capability failed: …` naming the sandbox's member.
- `sandbox.delete` removes the bridge from all members (verify on two).

Report as before: what was built, measured numbers, deviations, and
findings — especially anything about per-member dnsmasq/NAT behavior,
bridge activation time, or `restricted.networks.access` that Phases 3/5
should know before OVN replaces this mapping.
