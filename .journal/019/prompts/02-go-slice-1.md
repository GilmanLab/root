# Phase 2 — Go slice 1: a real agent creates, uses, rediscovers, and deletes a container sandbox

You are implementing slice 1 of the `agentcompute` Go server: the
`sandbox.*`, `image.list`, `instance.create/list/get/delete/exec`, and
`net.create/attach` capabilities over Incus containers with a per-sandbox
NAT'd default bridge. The measure of done is an MCP client — a real coding
agent — using `search_api` → `describe_api` → `execute` to stand up a
sandbox, run commands in a container, and tear it down, and the server
rediscovering everything after a restart.

## Read first

1. `/Users/josh/code/lab2/AGENTS.md`; the `agentcompute` repo's own
   `AGENTS.md`/`CONTRIBUTING.md` (generated from the template in Phase 1).
2. The design draft — the vocabulary is the contract:
   `/Users/josh/code/lab2/docs/docs/designs/drafts/agentcompute.md` (or the
   `.wt/feat-agentcompute-design/...` copy if not yet merged). Read
   "Vocabulary" conventions, the `sandbox`/`image`/`instance`/`net`
   tables, "Backend mapping", and "Open Questions" (resolved items are
   binding).
3. `/Users/josh/code/lab2/.wt/journal-jmgilman/.journal/019/ARCHITECTURE_GO.md`
   in full. It is the software architecture you are building: package
   layout, `compute` types and `Service` signatures, registration
   pattern, error contract (`codemode.AgentError`), state/concurrency
   (Incus as registry, keyed gate, reaper, capped exec writers),
   configuration, testing. Note the slice-1 specifics: `features.networks=false`,
   the default bridge `ac-<sandbox>-default` lives in the Incus `default`
   project, prefix stripped at the DTO boundary.
4. `/Users/josh/code/lab2/.wt/journal-jmgilman/.journal/019/PLAN.md`
   section 3 "Phase 2" and its verification/risk rows; section 2 Findings
   1, 3, 4, 5 (you will resolve 5 by building).
5. CodeMode's contract: `/Users/josh/code/meigma/codemode/docs/docs/reference/public-api.md`
   (`Capability`, input/output type rules, `Limits`, `AgentError`,
   `ServeWorkerAndExit`) and `mcp-tools.md`. The template's
   `internal/mcpserver/randomint.go`, `server.go`, `server_test.go`, and
   `docs/docs/how-to/add-a-capability.md` show the registration and
   in-memory MCP test patterns you must reuse.
6. Incus: `lxc/incus/client` Go package docs; the project reference
   (`features.*`, `restricted.*`, `restricted.networks.access`), the
   bridge network reference, and exec/file APIs.
7. Phase 1's report and `images/README.md` (catalog shape, imported
   `router` alias, `image-build` project, CI certificate).

## The spike that comes first

Two throwaway experiments, kept under `spikes/` and deleted or absorbed
before the PR merges:

1. **Project/bridge mapping with raw Incus calls.** Create two sandbox
   projects (`ac-a`, `ac-b`) with the exact features and `restricted.*`
   settings from `ARCHITECTURE_GO.md`, two bridges `ac-a-default` and
   `ac-b-default` in the `default` project, `restricted.networks.access`
   pointing each project at its own bridge, launch `router` in each with
   a NIC on its bridge, verify NAT egress and that `ac-a` cannot attach
   to `ac-b-default`, then delete everything and assert zero residue
   (`incus project list`, `incus network list`). Decision rule: if this
   mapping cannot be made to work under the intended restrictions, stop
   and report — do not invent a different network architecture.
2. **`AgentError` across the worker boundary.** One real capability on
   the template returning `&codemode.AgentError{Message: ...}`; confirm
   the MCP error text is `capability failed: <message>` through an actual
   `execute` call.

## Deliverables (in `agentcompute`, branch + worktree + PR)

Per `ARCHITECTURE_GO.md`, adding files only as the slice needs them:

- `cmd/agentcompute/main.go`; `internal/cli/{root,runtime,stdio,http}.go`
  (runtime builds deps once; HTTP is the deployment, stdio is dev-only).
- `internal/mcpserver/{server,sandbox,image,instance,net,convert}.go` with
  explicit `codemode.Register` per capability, flat-scalar DTOs, `{items}`
  roots, RFC3339 timestamps, initialized empty collections. Remove
  `random.int` and its tests.
- `internal/compute/{types,service,catalog,reaper,gate,errors}.go`:
  name grammar `[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?`, reserved `default`/`none`,
  generated sandbox names, TTL default 240 min, `user.agentcompute.*`
  metadata as specified, dependency-ordered deletion (forwards, NICs,
  instances, images/snapshots, networks, default-project bridges,
  project), reaper at startup + 30 s, keyed gate on control-plane
  mutations only, `ErrNotFound`/`ErrUnavailable`, `AgentError` for every
  agent-actionable failure, capped draining exec writers (64 KiB each),
  `ExecRequest.Argv = {"sh","-c",cmd}`.
- `internal/incus/{client,sandbox,instance,network}.go` over
  `lxc/incus/client`; request-scoped `UseProject`/`UseTarget`; never
  mutate a shared client.
- Catalog reconciliation at startup, reading the existing
  `images/catalog.yaml` (Phase 1's schema). `reference` comes in two
  forms and both must work: `ghcr.io/…@sha256:<imgoci digest>` for
  lab-built images (resolve → verify → import → smoke-launch → move
  alias, absorbing the Phase 1 `spikes/images` logic, then delete the
  spike) and an Incus alias like `images:ubuntu/24.04` for upstream
  images (ensure the remote exists; let Incus fetch on first use). Key
  on the imgoci digest, recorded on the imported image's properties;
  the Incus fingerprint is derived and changes on every rebuild
  (distrobuilder stamps timestamps) — never compare fingerprints across
  builds or across the local spike and CI.
- Restricted Incus certificates filter rather than 403 on reads outside
  their projects. Tests for "the server's identity cannot see the
  `default` project's instances" assert an empty list; tests for
  "cannot create there" assert the mutation error.
- Config file per the `ARCHITECTURE_GO.md` schema; hard-coded constants
  for everything it says is a constant. CodeMode `Limits`:
  `MaxExecutionTime` 15 m, `MaxNativeCalls` 1000.
- Tests per the "Testing" section: the discovery/signature contract test
  for the registered catalog; one in-memory MCP round trip; focused
  `compute` tests (name validation, expiry re-read after gate, extend
  semantics, reaper retry after partial delete, writer draining, timeout
  vs cancellation); mockery mocks of the small consumer interfaces only;
  `TestMain` with `ServeWorkerAndExit` first. Plus the opt-in integration
  lane (`-tags integration`, `AGENTCOMPUTE_TEST_REMOTE`) that runs the
  full create → exec → restart → discover → TTL-delete cycle against the
  cluster in a disposable project namespace.

## Working rules

- The vocabulary and signatures are fixed. If a signature cannot be
  honored (e.g. a field type CodeMode rejects), implement the closest
  honoring shape and report the deviation — do not silently rename.
- Keep the word `sandbox`; it is decided.
- `host?` on `instance.create` is honored (pin to that member) but there
  is no scheduler; default placement is the configured member.
- Nothing about OVN in this slice; `kind="ovn"` returns an `AgentError`
  saying it is not available yet.
- No cluster changes outside sandbox projects, their bridges, and what
  Phase 1's fleet work created. If you need a new cluster-side thing
  (a profile, a trust identity with broader rights), it goes through the
  `fleet` `cluster/` project in its own PR.
- Do not edit the design draft or `ARCHITECTURE_GO.md`; report findings.
- Commit often; Conventional Commits; squash-merge.

## Acceptance evidence

- Start `agentcompute stdio` against the cluster from a workstation and,
  from an MCP client, run the following as one `execute` program and
  paste the result: create sandbox (generated name), `image.list`,
  `instance.create` of `router` with defaults, `instance.exec` of
  `ip -br addr && nft list ruleset`, `net.create` of a bare bridge
  `lan`, `net.attach` to the router, `instance.get` showing two NICs,
  `sandbox.get`, `sandbox.extend`, `sandbox.delete`. Then `incus project
  list` and `incus network list` show no residue.
- Create a sandbox with one instance, kill the server, start it again,
  `sandbox.list` shows it with the original `expires_at`.
- Create a sandbox with `ttl_minutes=1`; within two minutes of expiry it
  and its bridge are gone without any call from the agent.
- `instance.exec` producing 1 MiB on both streams returns truncated
  output with both flags set and the server does not hang.
- `instance.get` on a nonexistent name yields `capability failed:
  instance "x" not found in sandbox "y"` at the MCP client.
- The integration lane passes; `moon run root:check` passes.

Report: what was built, deviations from the architecture and why,
measured behaviors (create latency, exec overhead), findings for the
design owner, and what Phases 3/5/6 must know (especially anything about
`features.networks`, project restrictions, or the default bridge that
will change when OVN arrives).
