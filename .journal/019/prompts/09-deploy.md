# Phase 9 — Deploy `agentcompute` as a cluster HTTP service and close the contract

Everything an agent needs now exists. This phase makes it a service: an
OpenTofu-owned VM on the cluster serving Streamable HTTP with real
authentication, the reaper running continuously so the TTL promise is
true, the runbook, the decision records, and the design draft promoted.
The acceptance bar is the draft's own "Validation" section, run by an
agent that is given nothing but `search_api`.

## Read first

1. Design draft in full — you are promoting it, so every "Validation"
   bullet, every "Resolved in review" item, and every prerequisite must
   be either true or explicitly recorded as a deviation in a new
   "Implementation Outcome" section (the template asks for one).
2. `ARCHITECTURE_GO.md` "Where the server runs" note, configuration,
   screenshot store (public base URL, mounted beside MCP), risks.
3. `PLAN.md` Phase 9, Findings 3 and 6.
4. The template's HTTP authentication seam: `template-mcp-codemode`
   README "Identity and authorization" (`ContextSubject`, the demo
   verifier sets `TokenInfo.UserID`; `--insecure` is dev-only) and
   `internal/cli/http.go`. CodeMode `mcpserver` docs on
   `InvocationResolver`. The lab has Zitadel planned as identity (VISION)
   but not live; a static bearer token from `GilmanLab/secrets` is the
   boring choice for a single operator — confirm with the owner.
5. Fleet OpenTofu roots from Phases 4/5 (`incus/incus-gh-runner/`,
   `incus/ovn-central/`) as the pattern; ADR-0005 for a TLS leaf
   certificate for the service; the documentation skill at
   `/Users/josh/code/lab2/.agents/skills/gilmanlab-documentation/SKILL.md`
   (runbook contract, decision records, design promotion via `git mv`).
6. `NOTES.md` in the session folder for the list of decisions that should
   become ADRs (OVN as sandbox fabric — Phase 5 opened it `proposed`;
   Cua Driver over exec as the desktop transport; Lume for macOS; CodeMode
   as the MCP style). Not every decision needs an ADR; the skill's
   "Decision contract" says when. Propose, do not over-produce.

## Deliverables

Infrastructure:

- `fleet` OpenTofu root `incus/agentcompute/`: a VM on the cluster (member
  of your choice; not `nas01` if `nas01` already carries OVN central and
  the runner controller — spread them), attached to VLAN 10 (Incus API)
  and VLAN 40 (guest reach, screenshot URL), running the released
  `agentcompute` binary or container image under systemd with credentials
  (Incus client cert restricted to `ac-*` project creation + the images
  it needs, Mac SSH key, bearer token) as systemd credentials. TLS leaf
  from ADR-0005 for the HTTP listener; `screenshots.base_url` set to the
  service's name. Pinned release version.
- `GilmanLab/secrets`: the service's credentials under the right scope.
- DNS name for the service via the lab's existing mechanism (CoreDNS on
  gw01 / the `glab.lol` zone — check the address plan and networking repo
  for how names are added); Tailscale reachability confirmed from a
  workstation.

Software (`agentcompute`):

- Release: first tagged release through the template's Release Please +
  GoReleaser + attestation path; container image on GHCR; the fleet root
  pins it.
- HTTP auth: replace the demo verifier per the owner's decision; subject
  recorded on sandboxes (`user.agentcompute.subject`) as already
  designed.
- Nothing else new. If a capability is missing or broken you have found a
  gap in an earlier phase: fix it there (own PR) and note it.

Documentation (root repo, one PR, following the documentation skill):

- `docs/docs/runbooks/agentcompute.md`: connect an agent (MCP config for
  the HTTP endpoint + token), verify with `search_api`, day-2 (restart,
  rotate token, reaper check, how to find and delete a stuck sandbox, how
  to re-consent the Mac seed), escalation.
- `docs/docs/architecture/agentcompute.md`: current-state architecture
  (context, building blocks, runtime flow, trust boundaries) written from
  the delivered system, not from the plan.
- Promote the design: `git mv docs/docs/designs/drafts/agentcompute.md
  docs/docs/designs/agentcompute.md`, status `implemented`, add
  "Implementation Outcome" with every deviation and the links; update
  `mkdocs.yml` nav; remove the "Resolved in review" block into the body
  where each item belongs.
- ADRs per the skill's decision contract (propose the set to the owner in
  the PR description; the OVN one exists as `proposed` — leave acceptance
  to the owner).
- Reference updates the earlier phases owed (address plan for any ranges
  not yet recorded; hardware inventory for the Mac).

## Working rules

- The owner reviews and accepts ADRs and the promoted design; you open
  the PRs.
- No `--insecure` on the deployed service.
- Do not read or modify `.journal/` of any session.

## Acceptance evidence (the draft's Validation section, verbatim)

- An agent, given only `search_api`, completes the representative program
  without operator help — over the deployed HTTPS endpoint, from a
  workstation, with the bearer token. Paste the program and result.
- A sandbox with `ttl_minutes=1` and one running VM is gone within two
  minutes of expiry with no residue in `incus project list`.
- A `client` on `lan` behind `rtr` reaches the internet and shows a
  routed source of `rtr`'s `wan` address from the `wan` side.
- Two instances on one OVN network placed on different members ping each
  other; a `net.forward` on the default network is reachable from the
  operator workstation.
- `desktop.screenshot` on a Windows guest returns an image in under 2 s
  after the desktop is ready.

Plus: the service survives a VM restart (`systemctl restart`) with all
sandboxes rediscovered; 8 concurrent blocking `execute` programs complete;
OpenTofu plan clean; `moon run docs:build` strict passes; the runbook was
followed once by someone other than you (or by you from a fresh shell
with no state) and worked.

Report: deviations from the design recorded in "Implementation Outcome",
what was deferred and why, and the ADR set proposed.
