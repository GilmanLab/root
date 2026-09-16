# Phase 9b — Close the contract: validate the deployed service, promote the design, propose ADRs

Phase 9a deployed `agentcompute` as a service; Phases 5–8 landed every
backend. This phase proves the design's own "Validation" section against
the deployed service and writes the documents that make the system
real to the next reader. Read `prompts/09-deploy.md` "Documentation",
"Working rules", and "Acceptance evidence" — those sections are the
contract; this file supplies the state of the world and the deviations
already known.

## Preconditions (check; stop and report if false)

- agentcompute `v0.1.2` or later is released and pinned in fleet
  (`incus/agentcompute/`), and `agentcompute01` runs it. v0.1.1 lacks the
  desktop capability PR (#26) and the Lume backend (#36).
- Merged: agentcompute#26 (desktop), #30 (catalog; #27 superseded), #36
  (Lume), fleet#20 (OVN trust roll + log bounds), root#34 (central
  recovery runbook), root#36 (operational runbooks), networking#22
  (tailnet policy).

## State of the world

- Service: `agentcompute01` on lab01, tailnet `100.65.152.20` /
  `agentcompute01.tailda715.ts.net`, `tag:agentcompute`, HTTPS via
  Tailscale Serve (public Let's Encrypt), static named bearer tokens as
  systemd credentials (identity `omp` exists; the token value is in
  `GilmanLab/secrets` `services/agentcompute/credentials.sops.yaml`).
  Incus credential is a dedicated **unrestricted** identity by approved
  exception — project creation is root-equivalent in Incus 7.4.
- OVN: durable central `ovncentral01` (nas01, `10.10.10.15`), dedicated
  offline OVN CA, chassis on all four members, `fast40-uplink` exclusive
  owner of `fast40`, `ipv4.ovn.ranges 10.10.40.64–.127`. Rules: control-
  plane operations need central up; `Errored` networks are reaper-
  deletable; `nat=false` networks are isolated segments with no uplink.
- Images: `router`, `runner`, `runner-publisher`, `ubuntu-24.04-desktop`
  baked on the lab (private `agentcompute-images` trigger repo, public
  `agentcompute` dispatches); Windows images cluster-local (Phase 7,
  agentcompute#28); macOS `macos/tahoe/desktop` seed on the Mac Studio
  under the `agentcompute` account (Phase 8, #29/#36).
- Snapshot restore on Incus is implemented as recreate-from-snapshot
  because restricted projects reject the snapshot's own volatile keys
  (Phase 5); confirm which shape landed and record it.

## Deviations already known (must appear in "Implementation Outcome")

1. Incus service identity is unrestricted (root-equivalent); the durable
   shape — a fleet-managed pool of pre-restricted `ac-NN` projects with a
   cert restricted to them — is deferred. Say why (OpenFGA model warning;
   scriptlet cannot see the project name at create time).
2. Image CI runs behind a private trigger repository because the org is
   on the free plan (no restricted runner groups) and the public repo must
   stay public for branch protection.
3. `fast40-uplink` exclusive ownership and the raw-macvlan lesson
   (Phase 3); OVN TLS as an application-scoped CA outside ADR-0005
   (Phase 5); the Phase 5 CA replacement that left three Incus daemons
   with stale trust and filled `ovncentral01`'s disk (fleet#20 — the
   recovery and the durable prevention).
4. macOS host is the owner's always-on Mac Studio under a confined
   standard account, not a dedicated box; Lume clones must have the
   seed's `machineIdentifier` pinned before first boot or they boot into
   Setup Assistant; Lume silently ignores a third macOS guest so the
   server counts; guest exec is direct SSH via ProxyJump, not `lume ssh`.
5. TLS for the HTTP listener is Tailscale Serve + public ACME, not an
   ADR-0005 leaf (no internal issuer exists yet).
6. Windows/macOS images carry no attestations; the release is not SLSA
   L3 (built outside the reusable attester).
7. Whole-desktop capture on the Linux desktop returned a black frame on
   v0.1.1 while window capture and AX worked (Phase 9a finding 3).
   Re-test on the current release; if it still fails, it is a gap to fix
   in the desktop code (own PR), not a validation footnote.
8. Residual: `sandbox.list` can transiently return not-found if another
   caller deletes a listed sandbox mid-list (Phase 8). Fix if cheap;
   otherwise record.

## Documents

Per `09-deploy.md`: the runbook `docs/docs/runbooks/agentcompute.md`
(root#36 may already cover part of it — extend, do not duplicate), the
architecture document written from the delivered system, the promoted
design with status `implemented` and "Implementation Outcome", nav
updates, and the reference updates earlier phases owed (address plan
ranges; hardware inventory entry for the Mac Studio's role).

ADRs — propose in the PR description, open each as `proposed`, owner
accepts: OVN as the sandbox network fabric (exists as `proposed`; update
with the outcome); Cua Driver over exec as the desktop transport; Lume on
a confined account for macOS guests; CodeMode as the MCP style (three
tools, Starlark programs, flat inputs). Do not write an ADR for anything
that is a configuration choice rather than a decision with alternatives.

## Acceptance evidence

Exactly `09-deploy.md` "Acceptance evidence", run against the deployed
HTTPS endpoint with the `omp` token from a workstation shell that holds no
state from earlier phases. In particular the representative program is
run by an agent given nothing but `search_api` — paste the program it
wrote and the result. Add: a macOS sandbox lifecycle (create, `sw_vers`,
`desktop.screenshot`, delete) through the same endpoint, since Phase 8
landed after the original prompt was written.

Report: deviations recorded, what was deferred and why, the ADR set
proposed, and every PR opened with its state. Do not edit `.journal/`.
