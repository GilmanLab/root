# Phase 3 — OVN mechanism spike

You are running the spike that decides whether OVN becomes the sandbox
network fabric for `agentcompute`. This is an experiment with a stated
decision rule, not a deployment. It runs in parallel with Phase 2 (the Go
slice) and must leave the cluster exactly as it found it, minus what the
`fleet` project deliberately keeps.

## Read first

1. `/Users/josh/code/lab2/AGENTS.md`; the `fleet` repo's README and
   `cluster/` project (`cluster/README.md`, `src/fleet_cluster/{config,operations}.py`,
   `deploys/`, `cli.py`, `moon.yml`, tests). Every change to cluster state
   goes through this project; you will extend it, not bypass it.
2. The design draft, "Design Overview" (OVN paragraphs), the `net`
   vocabulary table, "Lab prerequisites" 1–3, "Delivery" step 3, and the
   "Per-member bridge networks only" alternative (the fallback):
   `/Users/josh/code/lab2/docs/docs/designs/drafts/agentcompute.md`.
3. `/Users/josh/code/lab2/.wt/journal-jmgilman/.journal/019/PLAN.md`
   section 3 "Phase 3", section 4, and the Phase 3 verification/risk rows;
   section 2 Finding 2.
4. Current network facts (the shared notes are stale on this — trust git
   and the address plan): `/Users/josh/code/lab2/docs/docs/reference/networking/address-plan.md`
   (VLAN 30 storage on the fast links; VLAN 40 carried on the LAGs and
   nas01's link and declared host-side as `fast40`; instances attach with
   `parent=fast40`); fleet commits `2ef3177`, `d0e0b5e`, `ff9d4b0`;
   `NOTES.md` 12:41 entry in the session folder.
5. IncusOS OVN service reference:
   `https://linuxcontainers.org/incus-os/docs/main/reference/services/ovn/`
   and `incus-osd/api/service_ovn.go` (chassis only: `enabled`, `database`,
   TLS client material, `tunnel_address`, `tunnel_protocol`). Incus docs:
   "How to set up OVN with Incus", OVN network reference (`ipv4.nat`,
   uplink `ipv4.ovn.ranges`), network forwards, ACLs, peering; the project
   reference (`features.networks` requires OVN — this is the reason
   Phase 2 keeps bridges in the default project).
6. `sandbox01` facts in `TECH_NOTES.md` ("Sandbox host") — Ubuntu 26.04,
   reachable over Tailscale, its own Incus; you will run OVN central there
   temporarily.
7. pyinfra-incus (`meigma/pyinfra-incus`) — check whether it already has an
   `/os/1.0/services/ovn` operation; if not, follow how fleet added
   `/os/1.0` facts/ops before (the T49 history in `VISION.md` Tracker) and
   prefer filing an upstream issue over a fleet-local fork.

## The spike, in order

1. **OVN central on `sandbox01`**: `ovn-central` package (`ovn-northd`,
   NB/SB OVSDB), listening on plain TCP 6641/6642 on its VLAN 40 address
   for the duration of the spike only. Note that `sandbox01` is on VLAN 40
   and the nodes reach it via `gw01`; confirm reachability from the
   cluster members before configuring chassis. Plain TCP is the bounded
   spike allowance; TLS belongs to Phase 5.
2. **Chassis on all four nodes** through the fleet `cluster/` project: a
   new deploy that sets `/os/1.0/services/ovn` with `enabled`, `database`
   pointing at central, `tunnel_address` = each node's **VLAN 30** address
   (`10.10.30.1x`), `tunnel_protocol` geneve. Dry-run first; confirm the
   full-document PUT semantics IncusOS uses (see how the storage/network
   deploys handle confirmation timeouts) so a bad OVN document cannot cut
   management connectivity.
3. **Incus server config**: `network.ovn.northbound_connection` (and the
   matching SB/IC settings Incus requires) — read Incus's OVN setup guide
   for the exact keys on 7.4. This is cluster-wide config; through fleet.
4. **Uplink**: a temporary cluster-wide `physical` network with
   `parent=fast40` on every member and `ipv4.ovn.ranges` set to a small,
   explicitly reserved block that does not collide with gw01's DHCP pool
   (`.200`–`.250`) or `sandbox01` (`.10`). Pick from `10.10.40.64`–`.79`
   and say so. `ipv4.gateway=10.10.40.1/24`.
5. **One OVN network** in a disposable project with `features.networks=true`,
   `ipv4.nat=true`, DHCP on. Two `router` (or stock Alpine) containers on
   it placed on **different members** with `--target`. Prove: cross-member
   ping; internet egress (source NAT'd to the router's external address on
   VLAN 40); one `incus network forward` to a container port reachable from
   the operator workstation over Tailscale.
6. **Failure behavior**: stop central; verify the two containers still
   talk and egress; verify a *new* network creation fails cleanly; start
   central; verify creation works again.
7. **Teardown and repeat**: delete the project, network, forward; then
   recreate steps 5–6 from scratch. "Smooth" means the second pass needs
   no manual repair.
8. **Cleanup**: remove the uplink and the disposable project; leave the
   chassis service and Incus OVN config **only** if they are harmless
   with central stopped (verify a node reboot with central unreachable
   boots cleanly and management stays up). Otherwise revert them through
   fleet. Stop and remove `ovn-central` from `sandbox01` unless Phase 5 is
   starting immediately.

## Decision rule

Report **SMOOTH** if steps 5–7 pass through supported APIs and repeat
after teardown without manual intervention, and step 8's reboot check
passes. Report **NOT SMOOTH** with the exact failing step otherwise; the
design's documented fallback (per-member bridges, management NIC per
instance) is then the owner's call — do not decide it yourself and do not
"fix" it by inventing another network architecture.

## Deliverables

- `fleet` PR: the OVN chassis deploy (config-driven; central address and
  tunnel addresses in `config.py`), the Incus OVN server config, and the
  uplink network definition **kept but disabled/absent by default** if
  the spike is not smooth, enabled if it is. Tests in the existing style.
  If pyinfra-incus lacked an operation you needed, link the upstream
  issue/PR.
- `agentcompute` PR: `spikes/ovn/README.md` recording every command,
  observed output, timings, MTU findings (Geneve overhead over VLAN 30:
  check the instance MTU Incus chose and whether large transfers work),
  address consumption per OVN network (router external IP + forward IPs),
  and the failure-behavior observations. Plus `spikes/ovn/probe.sh` or a
  small Go program that runs the cross-member/egress/forward checks so
  Phase 5 can rerun them.
- Nothing in `networking` (no switch or gw01 changes) unless a firewall
  rule on gw01 is required for the forward to be reachable from Tailscale;
  if so, that is a separate networking PR and must be documented in the
  address plan.

## Working rules

- Read-only outside the disposable project except through fleet deploys.
- Never leave the cluster with a chassis config that cannot survive
  central being down.
- Record what breaks. The point is to learn.
- Do not edit the design draft; put findings in the report (the draft's
  "OVN central placement" and "VLAN 40 vs new VLAN" open questions are
  answered by your numbers).

## Acceptance evidence

- Transcript of steps 5–7 with the actual `ping`, `curl` (egress), and
  forward checks, the `incus network list --project …` output, and the
  second-pass timings.
- The reboot check output from step 8.
- `fleet` dry-run showing no diff after the final state.
- Your SMOOTH / NOT SMOOTH verdict with the one-line reason.
- The number Phase 5 needs: external addresses consumed per sandbox
  (router + typical forwards) so the owner can decide whether a /26 on
  VLAN 40 suffices.
