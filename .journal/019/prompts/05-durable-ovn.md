# Phase 5 — Durable OVN and the full Incus network/lifecycle contract

Phase 3 reported SMOOTH (if it did not, stop: this prompt does not apply
and the owner decides the fallback). You are now making OVN the real
sandbox fabric — a reviewed OVN central, TLS, the durable uplink — and
completing the Incus side of the vocabulary: the remaining `net.*`
capabilities, instance lifecycle verbs, `wait`, files, snapshots,
`publish`, and default least-loaded placement.

## Blocking decision

**VLAN 40 or a dedicated VLAN** must be decided before the durable uplink
is committed. The rule from the design: keep VLAN 40 if a reservation on
the order of a /26 in `10.10.40.0/24` covers the external addresses OVN
needs (virtual router per network + forwards), using Phase 3's measured
consumption. Present the numbers to the owner and get the call before
touching `networking` or the address plan. Do not pick for them.

## Read first

1. Phase 3's `spikes/ovn/README.md` and report; Phase 2's report
   (default-project bridges, `features.networks=false`, what the reaper
   deletes).
2. Design draft: `net` table, "Design Overview" OVN paragraphs, "Security
   and Privacy" (baseline ACL denying management/OOB), "Lab
   prerequisites" 1–3, "Validation", Open Questions (still open #1).
3. `ARCHITECTURE_GO.md`: the "later slices" methods on `compute.Service`,
   reaper deletion order, the `default_network_kind` flag semantics
   ("never an implicit rewrite of an explicit request", "existing bridge
   sandboxes are drained, not converted").
4. `PLAN.md` Phase 5 and Findings 4, 6.
5. ADR-0005 (internal PKI on the KMS root with sibling intermediates) at
   `/Users/josh/code/lab2/docs/docs/decisions/0005-…md` and the root-CA
   root in `GilmanLab/aws` for how leaf certificates are issued; Incus's
   CVE-2026-40243 advisory (OVN TLS trust flaw) — confirm the cluster's
   Incus version carries the fix before enabling TLS to OVN.
6. Fleet OpenTofu conventions for one-off VMs (Phase 4 created
   `incus/incus-gh-runner/`; mirror it).

## Deliverables

Infrastructure (fleet / networking / root docs, each its own PR):

- `fleet` OpenTofu root `incus/ovn-central/`: one VM on `nas01` attached to
  the VLAN 10 bridge (it must not depend on OVN), `ovn-central` installed
  and pinned, NB/SB listening with TLS using a leaf certificate from the
  ADR-0005 hierarchy; single node, no raft (decided). Backups of the
  NB DB are nice-to-have, not required — the consumer is disposable.
- `fleet cluster/`: the Phase 3 chassis deploy made durable — TLS client
  material per node (or one shared chassis identity, justify either),
  `tunnel_address` on VLAN 30, central's VLAN 10 address; Incus
  `network.ovn.*` config with the CA; the uplink `physical` network on
  `parent=fast40` with the decided `ipv4.ovn.ranges`. Seeds under
  `nodes/*/config.yaml` mirror runtime where IncusOS supports it (the
  project's existing rule).
- `GilmanLab/secrets`: OVN TLS keys under the fleet scope.
- Root docs PR: `address-plan.md` records the reserved OVN range on the
  chosen VLAN (and the new VLAN if that was the decision, with its trunk,
  firewall, and DHCP facts); the design draft's prerequisites 1–3 get
  their "done" status and the resolved VLAN question moves to "Resolved";
  a new ADR "OVN as the sandbox network fabric" (next free number,
  MADR, `proposed` — the owner accepts it).
- `networking` PR only if the decision was a new VLAN or a gw01 firewall
  rule is needed for forwards/ACL semantics.

Software (`agentcompute`):

- `net.create(kind="ovn")` as the default; per-sandbox `default` becomes
  an OVN network with NAT; sandbox projects created with
  `features.networks=true`; the config flag `default_network_kind` flips.
  Existing bridge sandboxes: reaper drains them by TTL; no live conversion.
- `net.peer`, `net.acl.add/remove` (with the baseline deny toward
  `10.10.10.0/24` and `10.10.70.0/24` installed by the server and not
  removable by agents), `net.forward`, `net.detach`, `net.impair`
  (Linux-only, `tc netem` in the guest; rejects others with `AgentError`).
- `instance.start/stop/restart`, `instance.wait(until=running|agent|network|stopped)`,
  `instance.file.read/write`, `instance.snapshot.*`, `instance.publish`
  (sandbox-scoped image, dies with the sandbox), default least-loaded
  placement across members (`host?` still honored).
- Reaper: full dependency order now exercised (forwards, NICs, instances,
  published images/snapshots, OVN networks, project). Prove `sandbox.delete`
  after `publish` + a forward + an ACL leaves zero residue.
- Tests: extend the discovery contract test; integration lane grows to
  cover cross-member OVN, peer routing, ACL, forward, snapshot, publish,
  and a management-VLAN probe that must fail.

## Working rules

- Everything cluster-side through fleet; nothing by hand except the
  Phase 3 spike teardown if it was left running.
- Keep the fallback alive in code: `kind="bridge"` continues to work for
  single-member bare wires.
- The design's `net` signatures are fixed. Report any field you could not
  honor.
- Do not accept the ADR yourself; open it `proposed`.

## Acceptance evidence

- Two instances on one OVN network on different members ping; the
  representative program from the draft's "A representative program"
  section runs end to end via MCP (router on `lan`+`wan`, client on
  `lan` only, `instance.get` shows the NICs) — minus the desktop lines,
  which are Phase 6.
- From a sandbox instance, `nc -zv 10.10.10.14 8443` and
  `nc -zv 10.10.70.20 443` fail (baseline ACL); an agent's
  `net.acl.remove` on the baseline rule returns an `AgentError`.
- A `net.forward` address is reachable from the operator workstation.
- `sandbox.delete` after publish + forward + ACL: `incus project list`,
  `incus network list --project …`, `incus image list --project …`
  show nothing owned.
- OVN central VM: OpenTofu plan clean; `ovn-nbctl --db=ssl:… show` works
  with the issued cert; a plain-TCP connection is refused.
- Node reboot with central stopped: management stays up, existing OVN
  flows persist.
- Address plan and ADR merged (ADR `proposed`); fleet dry-runs no-op.

Report: what changed, the VLAN decision and numbers behind it, deviations,
and anything Phase 6/9 must know (MTU, forward address exhaustion, reaper
timing under OVN).

## Handoff from Phase 2 (2026-09-11)

- Slice-1 sandboxes are `features.networks=false` projects with bridges
  `ac<8hex>` in the `default` project, mapped by `user.agentcompute.*`
  metadata (see `ARCHITECTURE_GO.md` "Default network, slice 1"). Drain
  and delete them (TTL or explicit delete) before enabling project-owned
  OVN networks; never rewrite a live topology. Keep the ownership checks
  and retryable deletion the reaper already has.
- The backend seam is `compute.Backend` (consumer-defined in `compute`,
  implemented by `internal/incus`). Add OVN/lifecycle methods to the
  interface only as the service calls them.
- Images are copied into each sandbox project before first use
  (`features.images=true` hides the `default` project's aliases);
  `instance.publish` must account for that copy when it creates
  sandbox-scoped images, and deletion must remove both.
- OVN networks inside a project create no host interface, so plain
  agent-facing names should be legal Incus names there — verify, and
  keep the metadata mapping anyway so the two kinds behave alike.
