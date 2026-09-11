# agentcompute implementation plan

Session 019, 2026-09-11. Produced by a read-only planner agent
(`agent://AgentcomputePlan`) from the design draft, `ARCHITECTURE_GO.md`,
`IMAGE_PIPELINE.md`, and this session's notes, with two mid-flight
corrections from Main: T48 is cleared and VLAN 40 already reaches the
cluster as `fast40` (fleet #9/#11/#12, networking #16–#19, root #24–#28);
and `features.networks` requires OVN, so slice-1 bridges live in the
Incus `default` project. Findings 1 and 2 have been applied to
`ARCHITECTURE_GO.md` and the design draft (`cce8670`). Designs otherwise
unchanged; the plan is advisory until Josh reviews it.

---

## 1. Critical evaluation

**Build the first published `router` image, then immediately exercise the Go worker with containers.** Neither the remaining image families nor the production OVN deployment belongs ahead of that feedback loop.

Citations below use **Design** for `agentcompute.md`, **Go** for `ARCHITECTURE_GO.md`, and **Images** for `IMAGE_PIPELINE.md`. All requested inputs, including the three underlying image reports, were read. The subsequent infrastructure correction supplied during this review supersedes the stale journal baseline: T48 is cleared, VLAN 40 reaches the cluster through `fast40`, and OVN tunnels can use `10.10.30.x`.

### Well-grounded

- **The vocabulary fits CodeMode.** Keyword-only scalar inputs, JSON strings at the desktop boundary, explicit readiness, and HTTP screenshot delivery respect its execution/value limits. `AgentError` is available in v0.2.1; it is not outstanding upstream work. The template’s actual `mcpserver.New` and `registerRandomInt` establish the registration pattern and immutable build boundary. [Design: “Vocabulary”; Go: “Capability registration,” “Error contract”; template README: “Worker entry points.”]
- **The Go structure is proportionate.** Handlers → `compute.Service` → Incus, metadata-backed discovery, a mutation gate, draining bounded output, and a re-scanning reaper address this workload without inventing a hypervisor framework. Deferring the Lume interface until real call sites exist is appropriate. [Go: “Summary,” “Decisions carried out of the review,” “State and concurrency.”]
- **The image pipeline matches the available execution environments.** Distrobuilder assembles without booting; real Incus VMs perform Windows installation and boot qualification; a bare-metal Mac runs Lume. Runner nesting remains disabled. GHCR publication and Incus import are distinct operations, correctly joined by reconciliation. [Images: “The shape that falls out,” “Publication and the last mile”; Linux/Windows/Mac reports: “Recommendation.”]

### What real execution must establish

The documents provide research, not completed image builds. Builder sizing, desktop session startup, Cua token continuity, Windows post-Sysprep behavior, and macOS permission survival remain experimental. The most likely implementation changes concern guest-session recipes, readiness deadlines, cleanup ordering, and catalog import details—not the five vocabulary roots. OVN still needs an operational central and uplink configuration, but extending VLAN 40 to the hardware is no longer prerequisite work. [Images: per-family sections; Go: “Risks”; Design: “Lab prerequisites,” “Open Questions.”]

## 2. Findings for the design owner

1. **The bridge/project mapping needs the correction authorized during this review.** Go’s “Default network, slice 1” places managed bridges inside projects with `features.networks=true`; Incus’s [project configuration reference](https://linuxcontainers.org/incus/docs/main/reference/projects/#project-features) says that feature requires OVN. The authorized mapping is bridges in the Incus `default` project, such as `ac-<sandbox>-default`, referenced from sandbox projects with `features.networks=false`. Spike project restrictions, collision-free physical names, and cleanup before implementing it. Question: does that exact mapping work under the intended restrictions without weakening isolation?
2. **The infrastructure prerequisite text is stale.** Design’s “Lab prerequisites” and VLAN-10 tunnel statements predate the cleared T48 blocker. Current `fleet_cluster.config` declares LACP and `fast40`; `desired_network_config` preserves management while adding the fast VLAN objects. The supplied correction confirms successful cross-node traffic. Remaining work is the cluster-wide physical OVN uplink and reserved external addresses—not new management-port trunks. Question: is VLAN 40’s current address allocation sufficient for the intended concurrent sandboxes and forwards?
3. **TTL is conditional on a live reaper.** Design’s “Nothing … outlives its TTL” is stronger than a reaper hosted in a workstation stdio process. The actual template exits when stdin closes; multiple such processes also have separate mutation gates. Spike disconnect, restart, and two-server access. Question: what operating conditions qualify the TTL acceptance promise before the persistent deployment?
4. **Deletion must cover more than the abbreviated algorithm.** Design’s `sandbox.delete` includes images and snapshots; Go’s reaper lists instances → networks → project. Published images, profile references, global slice-1 bridges, forwards, and partially completed operations can prevent completion. Spike deletion after publish/snapshot and cancellation during creation. The decision is whether the documented expiry-and-rescan mechanism actually converges without additional state.
5. **Several Go responsibilities are described twice or inconsistently.** Go’s “Summary” selects concrete adapters while “Testing” also proposes an Incus interface; “Error contract” assigns actionable errors to both service and handlers. Compile the smallest real slice and trace one not-found error before expanding these seams. Question: which exact ownership preserves the synthesized architecture without duplicate translations or import cycles?
6. **The catalog crosses two ownership boundaries.** Images selects digest-backed reconciliation, while Go’s configuration illustrates native aliases; `features.images=true` also separates sandbox images from imported global aliases. Prove digest → verified files → import → fingerprint launch in a restricted sandbox, including failed promotion. imgoci verifies content, not provenance policy. Question: which recorded publisher identity must be accepted when attesting and consuming releases? [Images: “Publication and the last mile”; imgoci spec: “What imgoci does not define.”]
7. **Desktop transport assumptions need one real agent.** Go explicitly excludes the base64 fallback still open in Design. A URL must work from the agent host, and the Driver’s structured JSON/binary file path must not accidentally inherit text-exec truncation. Spike two one-shot token-based calls and a real screenshot fetch. Question: does the current HTTP path satisfy the open question without a vocabulary change? [Go: “Request flow,” “Screenshot store”; Design: “Open Questions” 2, 8.]
8. **Platform qualification includes legal and operational gates.** Windows redistribution rights, cloned TPM/BitLocker state, interactive autostart after Sysprep, Mac TCC consent, and Lume’s tag-only pulls are unverified or restricted. A private registry is not license permission. Host-local Mac seeds are the research’s default, whereas Design’s catalog describes OCI references. Question: approve the exact local-seed/catalog interpretation and permitted distribution before the Mac slice; do not silently substitute it. [Images: Windows/macOS sections; underlying reports: “Risks and unknowns.”]

## 3. Implementation plan

### Workflow applying to every phase

Each touched repository gets its own branch, Worktrunk worktree, commits, and GitHub squash-merge PR. Inspect existing worktrees first; never use a root worktree to modify a child checkout. Cross-repository PRs link their dependencies. Paths below are repository-relative; paths described as **new** are planned deliverables, not existing infrastructure. Central lab documentation stays in `GilmanLab/root` under `docs/docs/`.

### Phase 1 — Publish and consume one `router` image

**Goal:** prove the entire image path before building image automation breadth.

**First spike and decision:** assemble the smallest pinned `router` system container; use a throwaway publisher/importer to round-trip its unified tarball through GHCR and imgoci. Settle the proposed `incus-container` extension and explicit role selection before publication. Pass only if the pinned imgoci implementation resolves the complete artifact, verifies bytes, and Incus imports and launches it. Do not disguise it as `incus-vm` if validation fails.

**Deliverables/files:** generate `GilmanLab/agentcompute` from the template; update `go.mod`, `go.sum`, and generated project identities. Add `images/pins.yaml`, `images/router/distrobuilder.yaml`, `images/catalog.yaml`, `.github/workflows/images-publish.yml`, and temporary `spikes/images/main.go`. Retain the existing attest/rehearsal conventions. In fleet, add `cluster/src/fleet_cluster/deploys/image_build.py` and wire it through `cli.py`, `pyinfra_runner.py`, and `cluster/moon.yml` for the dedicated build project/credential baseline. Publish one digest, attest it, fetch it independently, and launch its imported fingerprint. Use hosted assembly if it fits; otherwise assemble on `sandbox01`. Neither choice requires nested KVM.

**Dependencies/learning:** no sandbox-name, Mac, final VLAN, or session-018 answer. Record wall time, peak memory, scratch maximum, and artifact sizes. Representation or scoped-credential failure invalidates publication assumptions, not the image-builder choice. Stop here on image breadth and move to Phase 2.

### Phase 2 — Go slice 1: containers and bridge default

**Goal:** an actual agent creates, uses, rediscovers, and deletes a container sandbox.

**First spike and decision:** reproduce the authorized global-bridge/project mapping with direct Incus calls, including restricted NIC attachment, two simultaneous sandboxes, `host`, and deletion. If it fails, stop this mapping for owner resolution; do not add a different network architecture. Separately compile the template worker with one real capability and demonstrate `AgentError` across its worker boundary.

**Deliverables/files:** `cmd/agentcompute/main.go`; `internal/cli/{root,runtime,stdio,http}.go`; `internal/mcpserver/{server,sandbox,image,instance,net,convert}.go`; `internal/compute/{types,service,catalog,reconcile,reaper,gate,errors}.go`; `internal/incus/{client,sandbox,instance,network}.go`. Add files only when the slice needs them. Remove `random.int` and its demo consumers. Implement the Go proposal’s slice-1 capabilities, metadata/subject, TTL, bounds, deadline behavior, and fixed-member placement. Honor supported explicit `host` placement rather than silently discarding it. Reconciliation now belongs to server startup/catalog application, not a second service. Test imported-image visibility inside sandbox projects.

**Dependencies/learning:** Phase 1 proves the artifact path. **The word `sandbox` becomes blocking before durable agent-facing registrations/saved examples are committed**, not before image or direct-API experiments. Keep the name as written until the owner decides. Initial bridge use is controlled prototype use, not proof of the final sandbox-VLAN security boundary. Failed cleanup, cross-project image access, or worker lifecycle assumptions invalidate later lifecycle work.

### Phase 3 — OVN mechanism spike, parallel with Phase 2

**Goal:** prove central, chassis, cross-member traffic, NAT, and forwards before productionizing them.

**First spike and decision:** run temporary `ovn-central` on `sandbox01`; configure all four chassis with VLAN-30 `tunnel_address` values through fleet. Use the existing `fast40` attachment for a temporary physical uplink with explicitly reserved, conflict-checked external addresses. Require cross-member ping, internet egress, and a workstation-reachable forward. Observe behavior during central interruption and restart. “Smooth” means these work through supported APIs and repeat after teardown/recreation, without recurring manual repair. Otherwise invoke Design’s documented bridge fallback decision with the owner.

**Deliverables/files:** new `agentcompute/spikes/ovn/probe.sh`; fleet `cluster/src/fleet_cluster/deploys/ovn.py`, `config.py`, existing CLI/runner/task entrypoints. No networking trunk changes. Use central’s plain-TCP allowance only within the bounded spike.

**Dependencies/learning:** independent of Go registration and image-family completion. Existing VLAN 40 is sufficient for a bounded experiment; the final VLAN choice is not yet blocking. Discover MTU, address consumption, API restrictions, central reachability, and failure behavior. Failure invalidates durable OVN and cross-member placement phases.

### Phase 4 — Move image CI onto lab runners

**Goal:** remove hosted-builder limits only after the first image and first Go feedback exist.

**First spike and decision:** build one minimal runner VM image using the proven path, then execute one protected router build through `incus-gh-runner` v2.0.0 pinned HTTPS mode. Require loop/mount assembly to work while `security.nesting=false` remains unchanged and bake/boot operations run on the cluster.

**Deliverables/files:** agentcompute `images/runner/distrobuilder.yaml`, `images/pins.yaml`, image workflow; new fleet `incus/incus-gh-runner/{main,variables,outputs}.tf` and cluster runner-baseline deploy. Cluster-awareness changes belong in a separate `meigma/incus-gh-runner` PR touching `deploy/incus/cue/deployment.cue`, `deploy/incus/policy.go`, and `internal/incusvalidate/validator.go` plus its actual snapshot reader if required. The current `validateServer` explicitly rejects the dedicated-host/cluster mismatch; do not bypass validation.

**Dependencies/learning:** after Phases 1–2; parallel with OVN qualification. Publisher jobs run only protected code with scoped privileges, separate from untrusted PR runners. Learn real capacity and whether certificate restrictions cover the required operations. Failure leaves the successful initial build route usable.

### Phase 5 — Durable OVN and full Incus lifecycle/network capabilities

**Goal:** replace temporary central/uplink state with reviewed infrastructure and complete the Incus contract.

**First spike and decision:** qualify the reserved external-address block and full firewall path on existing VLAN 40; prove management/OOB denial, including attempted agent ACL changes. **VLAN 40 versus a new VLAN becomes blocking here, before committing the durable uplink/address allocation.** If keeping VLAN 40, do not rebuild its already working attachment. A replacement VLAN requires its own explicitly approved networking change.

**Deliverables/files:** new fleet `incus/ovn-central/{main,variables,outputs}.tf`; existing OVN deploy and `nodes/{nas01,lab01,lab02,lab03}/config.yaml` for supported seed parity. Central runs independently of OVN on `nas01`’s VLAN-10 bridge; chassis tunnels use VLAN 30. Deploy TLS from ADR-0005 with an Incus version verified to contain the cited security fix. Root `docs/docs/reference/networking/address-plan.md` records ranges; networking `vyos/gw01/config.boot.tmpl` changes only if reservations/policy require it.

Extend existing Go service/adapters/DTOs with lifecycle verbs, readiness, text files, snapshots, sandbox publication, remaining `net.*`, and the draft’s default least-loaded placement. Drain/delete prototype bridge sandboxes before enabling `features.networks=true`; do not rewrite live topologies. Preserve explicit bridge requests and unsupported-operation errors.

**Dependencies/learning:** Phases 2–3. Prove publish/snapshot cleanup and mixed network behavior. Address exhaustion, ineffective ACL boundaries, or project conversion constraints invalidate unrestricted use and final deployment.

### Phase 6 — Linux desktop and `desktop.*`

**Goal:** qualify one desktop image and the actual screenshot/action transport.

**First spike and decision:** boot a pinned Ubuntu/Xorg candidate, start the approved Cua release in the user session, capture a window token, and use it through a second one-shot exec invocation. Fetch the resulting image from the real agent host. Continue only if semantic input, capture, restart, and URL reachability work; unresolved transport/token behavior returns to the owner’s open questions.

**Deliverables/files:** `images/ubuntu-24.04-desktop/distrobuilder.yaml` and its GDM/user-unit files; pins/catalog/workflow updates; `internal/desktop/{driver,store}.go`, `internal/mcpserver/desktop.go`, and existing compute file/exec and CLI HTTP wiring. Preserve bounded JSON parsing, binary screenshot pulls, transient storage, and VNC fallback.

**Dependencies/learning:** Phase 2 and a builder with measured capacity; OVN production is not required for this spike. Phase 5 enables the final isolated-topology demonstration. Learn headless-session behavior, output sizes, latency, and JSON-string usability. A successful screenshot alone does not qualify semantic actions.

### Phase 7 — Windows and router impairment

**Goal:** add Windows without changing the pipeline, and exercise the published router in real topologies.

**First spike and decision:** repack pinned media, install one cluster VM, generalize, capture, and launch a fresh clone with the runtime Agent CD, TPM, and Secure Boot settings. Require Incus exec, decrypted capture state, interactive Driver startup, input, and screenshot. Licensing approval blocks publication, not permitted local evaluation. In parallel, prove forwarding and `tc netem` in a restricted router container.

**Deliverables/files:** `images/windows/common/{instance.yaml,bootstrap.ps1,finalize.ps1,smoke.ps1}`; Windows 11 and Server-2025 answer-file directories; `.github/workflows/windows-images.yml`; pins/catalog; `images/router/files/opt/router/` helpers; existing Go instance/network/desktop files. Server 2025 remains Server Core. Implement `net.impair` with explicit rejection on non-Linux guests.

**Dependencies/learning:** Phases 4–6 for the intended release route. Learn Sysprep/session survival, independent TPM behavior, snapshot/restore behavior, capture latency, and restricted-container networking limits. Failure blocks that family’s promotion, not Linux use.

### Phase 8 — macOS via Lume

**Goal:** qualify the second backend from real behavior before extracting interfaces.

**First spike and decision:** **the Mac-host answer becomes blocking at the first VM/TCC experiment**, not during previous phases. On that host, create a pinned Sequoia seed, obtain supported human TCC consent, stop/clone/boot, and prove SSH, semantic input, capture, and permission survival. Decide Lume’s provisional suitability using NAT-only access, stability, snapshot-as-clone, and two-guest capacity. Failure invokes the already documented alternative review; no automatic substitution.

**Deliverables/files:** `images/macos/sequoia/desktop/{image.yaml,unattended.yaml,provision.sh,verify.sh}`; pins/catalog and protected serial Mac workflow; new `internal/lume/{client,sandbox,instance}.go`; consumer-sized interfaces extracted from existing compute/desktop call sites. Implement sidecar metadata, restart discovery, TTL, clone snapshots, and explicit `net.*` rejection. Apply the owner-approved seed/catalog interpretation from Finding 8; registry publication remains conditional on legal approval.

**Dependencies/learning:** Phase 6’s desktop mechanism. Prove access from server → Mac → NAT-only guest, not direct server-to-guest routing. Permission or tag/digest failures can invalidate reproducible seed delivery.

### Phase 9 — Deploy and close the contract

**Goal:** a persistent cluster service usable by an agent without operator assistance.

**First spike and decision:** run the complete discovery-only acceptance exercise over authenticated Streamable HTTP, including restart and expiry. Promote only when all named Design validation checks pass; do not label Linux-only delivery complete.

**Deliverables/files:** new fleet `incus/agentcompute/{main,variables,outputs}.tf`; agentcompute runtime/HTTP deployment configuration and release settings; root `docs/docs/runbooks/agentcompute.md`, address/reference updates, and an owner-reviewed OVN ADR using the next available number. Promote the draft only through the owner’s separate design PR. Session 018 remains unread unless authorized; its answer is never a technical prerequisite, only an optional prior-art review before closure.

**Dependencies/learning:** all platform and security gates. Restart, long blocking programs, simultaneous requests, and reaper behavior determine whether the deployment satisfies the promised operating model.

## 4. Critical path and parallelism

The shortest useful path is **Phase 1 → Phase 2 → first agent feedback**. Do not insert runner productionization or desktop polishing between them.

OVN Phase 3 runs beside Go slice 1. Runner Phase 4 and Linux desktop experimentation can proceed independently of durable OVN, provided their build/guest resources are separate. Phase 5 requires successful OVN evidence and the durable VLAN decision. Windows licensing inquiries and static answer-file preparation can run earlier, but image promotion serializes behind clone qualification. Mac preparation needs no hardware selection; VM/TCC work does.

Serialize shared fleet/networking applies and shared Go-file edits even when investigations run concurrently. The final representative topology depends on OVN, Linux desktop, and router behavior; final acceptance also requires Windows and macOS.

## 5. Verification per phase

These are future execution criteria, not claims that this read-only planning task ran them.

| Phase | Observable completion evidence |
|---|---|
| 1 | `distrobuilder build-incus … --type=unified`; independent digest fetch; `incus image import`; launch exact fingerprint and execute required router tools. Failed verification leaves the prior alias unchanged. |
| 2 | Launch actual `agentcompute stdio`; `search_api` → `describe_api` → `execute` creates, execs, lists, extends, and deletes. Restart rediscovers metadata. Concurrent stdout/stderr beyond their caps drains without hanging; cancellation leaves recoverable named resources. |
| 3 | Containers explicitly on different members ping; NAT reaches internet; returned forward is workstation-reachable; repeat after central restart and complete teardown. |
| 4 | One protected job assembles and publishes; remote cluster performs boot test; nesting remains false; wrong pinned server certificate and out-of-project operations fail. |
| 5 | Cross-member OVN, peer routing, attach/detach, ACL add/remove, forwards, lifecycle, files, snapshots, and publish operate through MCP. Management/OOB probes fail. Delete leaves no owned project, image, profile reference, bridge, or forward. |
| 6 | Real agent reads screenshot URL, uses a fresh semantic token, observes the changed application, and repeats after guest restart; VNC mirrors the session. |
| 7 | Fresh generalized Windows clone passes GUI/exec checks; ready Windows screenshot returns an image in under two seconds. Server Core exec works. Router WAN capture proves translated source; impairment changes measured traffic and clears. |
| 8 | Disposable Mac clone needs no new consent; SSH/file/action/screenshot/snapshot paths work; server restart discovers it; expiry removes it; unsupported networks fail clearly. |
| 9 | Agent given only `search_api` completes Design’s representative program. A one-minute sandbox containing a running VM disappears within two minutes after expiry. Authenticated HTTP, screenshot reachability, restart, and concurrent blocking calls pass. |

## 6. Risks and rollback per phase

- **1:** Root assembly and registry publication are privileged. Use disposable build resources; retain the previous digest/fingerprint and restore its alias on failure.
- **2:** Temporary bridges lack the final security boundary. Restrict experiments, track global bridge ownership, and explicitly remove prototype resources before cutover. Reaper failure is not successful cleanup.
- **3:** Central/chassis changes can affect networking. Preserve prior service documents, remove only spike objects, restore chassis configuration, and keep central independent of OVN.
- **4:** Publisher credentials and root access must not reach PR code. Stop the controller, revoke its scoped certificate, and resume the already-proven initial build route.
- **5:** Preserve management connectivity during full-document IncusOS updates; use confirmation/rollback behavior. Keep prior central configuration and address allocation; never roll back by moving active instances between network kinds.
- **6:** Bad desktop images or unreachable URLs block promotion. Retain the prior digest; delete temporary screenshots and candidate instances; do not substitute base64 silently.
- **7:** Never reboot the generalized source. Retain it stopped until clone qualification completes; withhold publication on licensing, encryption, or session failures.
- **8:** Preserve the stopped consented seed; never overwrite it with a failed clone. Keep credentials outside images and remain within the two-running-guest limit.
- **9:** Roll back the binary/config and VM deployment independently while preserving Incus/sidecar metadata. Keep the reaper supervised during rollback; stop new requests rather than claiming expiry works with no running service.