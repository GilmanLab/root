# Phase 1 — Bootstrap `GilmanLab/agentcompute` and publish one `router` image end to end

You are implementing Phase 1 of the agentcompute plan. The goal is narrow
on purpose: create the repository, then get **one** image — the `router`
system container — from a pinned recipe in git, through CI, into GHCR as
an imgoci release, and imported and running on the lab's Incus cluster.
Nothing else. Do not start on the desktop images, Windows, macOS, or the
Go server; those are later phases with their own prompts.

## Read first

1. `/Users/josh/code/lab2/AGENTS.md` and `/Users/josh/code/lab2/.session.md`
   (repository protocol; session lifecycle is not your concern unless asked).
2. The design draft, "image" catalog section and "Lab prerequisites":
   `/Users/josh/code/lab2/docs/docs/designs/drafts/agentcompute.md`
   (if absent on master, use
   `/Users/josh/code/lab2/.wt/feat-agentcompute-design/docs/docs/designs/drafts/agentcompute.md`).
3. `/Users/josh/code/lab2/.wt/journal-jmgilman/.journal/019/PLAN.md`,
   section 3 "Phase 1" and section 5/6 rows for Phase 1.
4. `/Users/josh/code/lab2/.wt/journal-jmgilman/.journal/019/IMAGE_PIPELINE.md`
   in full, then `research/linux-images.md` beside it for the distrobuilder
   detail, options table, and pinning guidance.
5. The template you will generate from: `/Users/josh/code/meigma/template-mcp-codemode/README.md`.
6. imgoci: `/Users/josh/code/imgoci/spec/README.md` and
   `/Users/josh/code/imgoci/go/README.md` (Go client; note it is pre-v1 —
   pin an exact module version).
7. Cluster facts: `incus cluster list nas01:` (Incus 7.4, four IncusOS
   members), `/Users/josh/code/lab2/fleet/cluster/README.md` and
   `cluster/src/fleet_cluster/` (all cluster configuration flows through
   this pyinfra project; you do not run ad-hoc `incus` commands that change
   cluster state outside a disposable project).

## Repository bootstrap

- Create `GilmanLab/agentcompute` from the GitHub template
  `meigma/template-mcp-codemode` (private unless Josh says otherwise; the
  tool is lab-specific). Follow the template README's post-generation
  steps: module path `github.com/GilmanLab/agentcompute`, binary
  `agentcompute`, `TEMPLATE_MCP_CODEMODE_*` → `AGENTCOMPUTE_*`, release
  app credentials, `ghd.toml`, image name. Bump `github.com/meigma/codemode`
  to **v0.2.1** or later (`AgentError` is required later; pin it now).
  Leave the `random.int` demo in place until Phase 2 replaces it.
- Register the sub-repository in the meta repo: add `clone_repo agentcompute`
  to `/Users/josh/code/lab2/init.sh` and `/agentcompute/` to
  `/Users/josh/code/lab2/.gitignore`, and mention it in the
  "Sub-repository workflow" paragraph of `AGENTS.md`. That is a root-repo
  PR. Clone the new repo to `/Users/josh/code/lab2/agentcompute`.
- The `docs/` tree that the template generates is the repo's *own* MkDocs
  site; keep it for engineering docs, but all lab documentation stays in
  the meta repo under `docs/docs/` per `AGENTS.md`.

## Deliverables

In `agentcompute` (branch + Worktrunk worktree + squash-merge PR, per
`AGENTS.md`):

- `images/pins.yaml` — distrobuilder version and release SHA-256; Alpine
  (or Debian) release and exact package versions; anything downloaded, by
  URL + SHA-256. This file is the reproducibility root.
- `images/router/distrobuilder.yaml` — a system-container recipe with
  `nftables`, `frr`, `iproute2` (with `tc`), `dnsmasq`, `wireguard-tools`,
  `tcpdump`, and nothing else. No helper scripts yet (Phase 7 adds
  `/opt/router/`). Unified tarball output.
- `images/catalog.yaml` — one entry: `router`, its GHCR reference **by
  digest**, kind `container`, OS/version, defaults. This is the file the
  Go server will read in Phase 2; keep its shape close to the
  `images:` block in `ARCHITECTURE_GO.md` "Configuration".
- `.github/workflows/images-validate.yml` (pull requests: schema/pin
  checks, no credentials) and `images-publish.yml` (protected `master`
  and `workflow_dispatch`: build, boot-test, publish, attest). Pin every
  action by full commit SHA, minimal permissions, per the template's CI
  conventions.
- A throwaway `spikes/images/` tool (Go, using `imgoci/go`) that resolves
  the release by digest, fetches and verifies the unified tarball, and
  runs `incus image import … --alias router` against a named remote and
  project. It is allowed to be ugly; it will be absorbed into the Go
  server's reconciler in Phase 2. Say so in its README.

In `fleet` (its own branch/worktree/PR): whatever the `cluster/` pyinfra
project needs to create a dedicated **`image-build`** Incus project on the
cluster (restricted, its own profile, a bridge or the existing `fast40`
attachment for egress) and a trust identity for CI restricted to that
project. Study how existing deploys are structured (`deploys/`, `cli.py`,
`moon.yml`) and follow them exactly; do not invent a parallel mechanism.

## The spike that comes first

Before writing workflows, assemble the router tarball locally (or on
`sandbox01` if your machine cannot run distrobuilder — it needs root and
loop devices, not KVM), push a **throwaway** imgoci release to a scratch
GHCR repository, fetch it back by digest with `imgoci/go`, import it into
the `image-build` project, launch it, and run `nft --version`, `vtysh
--version`, `tc -V`, `dnsmasq --version`, `wg --version`, `tcpdump
--version` inside. Decision rule: proceed only if the pinned imgoci
client resolves the release, verifies bytes, and Incus launches the
imported fingerprint. imgoci standardizes `incus-vm` but has no container
representation; settle one (proposed `incus-container`, roles TBD from
the spec's extension rules) and record the choice in `images/README.md`.
Do **not** mislabel the container as `incus-vm` to make validation pass.

## CI runner choice

Use a GitHub-hosted Ubuntu runner for this phase if distrobuilder's
root/loop requirements and the 14 GB disk suffice for a small Alpine
container image; otherwise assemble on `sandbox01`. Do not set up
`incus-gh-runner` here (Phase 4). Boot-tests run on the cluster through
the Incus API with the restricted CI certificate, never inside the runner.

## Working rules

- Pinned versions everywhere; no floating "latest".
- Do not modify the design draft or `ARCHITECTURE_GO.md`. If reality
  disagrees with them, write the disagreement into your final report
  under "Findings for the design owner".
- No cluster-wide changes outside the `image-build` project and the
  fleet-owned pieces above.
- Record on the first three builds: wall time, peak RSS, scratch
  high-water mark, artifact sizes. Put the numbers in `images/README.md`.
- Commit often; PR titles are Conventional Commits; squash-merge via
  GitHub.

## Acceptance evidence (put the actual output in your report)

- `gh release` / GHCR shows one imgoci release for `router` with an
  immutable tag and a recorded digest; `gh attestation verify` passes.
- From a clean clone, `spikes/images` resolves that digest, imports it,
  and `incus --project image-build launch router t1` followed by the six
  version commands succeeds; `incus --project image-build delete -f t1`.
- `images-publish.yml` ran once on `master` and produced the same digest
  as the local spike (or you explain the difference in bytes: timestamps
  are the expected culprit — see the Linux report's reproducibility notes).
- Root-repo PR merged: `init.sh` clones `agentcompute`.
- A short `images/README.md`: how to build locally, the representation
  decision, measured numbers, and what is throwaway.

Finish with a report: what was built, what was learned, measured numbers,
findings for the design owner, and anything Phase 2 must know.
