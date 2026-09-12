# Phase 4 (resume) — Lab runners behind a private trigger repository

You are resuming Phase 4 of agentcompute. The previous attempt stopped
correctly at the public-repository threat gate: a repository-scoped runner
is selectable by any workflow in that repository, including fork
`pull_request` workflows after approval, so "fork PRs can never select the
publisher label" cannot be made true at repository scope. Your recommended
fix — an organization runner group with `restricted_to_workflows` — is
unavailable: the GilmanLab organization is on the **free** plan and will
stay there; runner groups need GitHub Team. Making `agentcompute` private
was also rejected: on the free plan it would lose branch protection (which
the publisher's protected-`master` gate depends on), unlimited Actions
minutes, CodeQL, secret scanning, and attestations.

The original prompt (`prompts/04-lab-runners.md`) still applies except
where this file changes it. Read it first, then this.

## The decided shape

The self-hosted scale set lives in a **new private repository**,
`GilmanLab/agentcompute-images`. The public repository never has a runner.

| Repository | Visibility | Runs on | Contains |
|---|---|---|---|
| `GilmanLab/agentcompute` | public (unchanged) | GitHub-hosted only | source of truth: `images/` recipes, pins, `catalog.yaml`, PR validation, and a `publish` job on protected `master` that only *dispatches* |
| `GilmanLab/agentcompute-images` | private (new) | the incus-gh-runner scale set | one `bake.yml` workflow, triggered by `repository_dispatch` (type `images-publish`) and `workflow_dispatch`; nothing else |

Flow: push to protected `master` in `agentcompute` → GitHub-hosted
`publish` job validates and sends `repository_dispatch` with
`client_payload.sha = $GITHUB_SHA` → `bake.yml` in the private repo checks
out **the public repository** at that SHA, refuses unless
`git merge-base --is-ancestor <sha> origin/master`, builds with
distrobuilder on the lab runner, boot-tests against the cluster, publishes
to GHCR, and opens the catalog digest PR in `agentcompute` exactly as the
current publisher does.

Why this holds: the runner label exists only in a repository whose
writers are organization members (currently one). Fork workflows in the
public repository cannot reference it, cannot read the public
repository's secrets, and the dispatch runs only from the protected
`master` push job. The private repository has no branch protection on
the free plan; that is acceptable because it holds no source of truth —
the bake takes recipes from the public repository by SHA with the
ancestry check above.

## Tokens

Use one **dedicated GitHub App** (`agentcompute-images-bot` or similar),
separate from the controller's App, installed on the organization with
the minimum permissions: `contents: write` on `agentcompute-images` (to
dispatch) and `contents: write` + `pull_requests: write` on `agentcompute`
(to open the catalog PR). Mint tokens in workflows with
`actions/create-github-app-token`. The App private key goes in each
repository's Actions secrets (fork PRs cannot read secrets; the public
job is protected-`master` only) and in `GilmanLab/secrets` per its SOPS
conventions. A fine-grained PAT is acceptable only if the App is blocked;
record its expiry in `images/README.md` if you use one.

GHCR: keep the existing package names (`ghcr.io/gilmanlab/agentcompute/…`)
so the catalog and reconciler are unchanged. Grant the private repository
write access on those packages (package settings → Actions access) rather
than publishing under a new namespace.

## Public-repository hygiene (do these; they are cheap)

- `IMAGES_RUNNER` repository variable: delete it; `runs-on` in the public
  repository becomes a GitHub-hosted constant again.
- `gh api repos/GilmanLab/agentcompute/actions/permissions`: set
  `sha_pinning_required: true`.
- Fork approval policy: `all_outside_collaborators`.
- Verify and record: `gh api repos/GilmanLab/agentcompute/actions/runners`
  → `total_count: 0`; the public publisher triggers only on `push` to
  `master` and `workflow_dispatch`; `bake.yml` triggers only on
  `repository_dispatch` and `workflow_dispatch` — never `pull_request` /
  `pull_request_target` in either.

Record the threat review in `images/README.md` with this shape and these
checks. If any check cannot be made true, stop and report.

## incus-gh-runner on the cluster

Verified from source at v2.0.0: the controller **runtime never checks
clustering**. `ServerState.Clustered` is read only by the operator-run
`validate` subcommand (`internal/incusvalidate/validator.go:113`), and
`standalone: true` / `cluster_https_address: ""` are constants in
`deploy/incus/cue/deployment.cue:213-218`. The cluster-aware baseline is
tracked upstream — see the issue linked in `NOTES.md` under
"2026-09-12 — Phase 4 resume" (filed by the session owner). Do the
upstream PR if you can do it cleanly (a cluster server profile in the
CUE: `standalone: false`, concrete member `cluster_https_address`; the
two hard-coded checks become baseline-driven; `firewall_driver` and the
extension list re-verified against IncusOS/Incus 7.4). Deploy the
controller against the cluster regardless; run `validate` once a release
containing the fix exists and record the gap until then. Do not bypass
or patch the validator locally.

Controller placement and connection are unchanged: OpenTofu-owned VM on
the cluster, `incus.url https://10.10.10.14:8443`, pinned cluster server
cert, client cert restricted to `github-runners` + `image-build`.

## Deliverables (delta from the original)

- New repository `GilmanLab/agentcompute-images` (private) with `bake.yml`,
  a README stating what it is and is not (no source of truth; dispatch
  target only), and the scale set bound to it. Register it in the root
  repository's `docs/` where the image pipeline is documented, not in
  `init.sh` (nothing to clone locally).
- `agentcompute` PR: `images/runner/…` recipe(s) and pins; the publisher
  reduced to validate-and-dispatch on protected `master`; `IMAGES_RUNNER`
  removed; skip-when-tag-exists kept; threat review in `images/README.md`.
- Everything else in the original Deliverables list (fleet `cluster/`
  deploy for `github-runners`, OpenTofu controller root, secrets PR) is
  unchanged.

## Acceptance evidence (delta)

- One end-to-end run: a `master` push in `agentcompute` → dispatch →
  `bake.yml` on the lab runner (job log shows the lab hostname) → GHCR
  digest → catalog PR opened in `agentcompute` by the bot → runner VM
  deleted.
- Negative: a `bake.yml` `workflow_dispatch` with a SHA not on public
  `master` refuses before building.
- `gh api repos/GilmanLab/agentcompute/actions/runners` → 0 after
  everything is enabled.
- The original acceptance items (boot-test transcript, controller
  journal, restricted-cert negative checks, measured latency/wall time,
  fleet/OpenTofu no-op) still apply.

Report with findings; do not edit the design documents or anything under
`.journal/`.
