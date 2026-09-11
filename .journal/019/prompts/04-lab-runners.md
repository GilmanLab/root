# Phase 4 — Move image CI onto lab runners with incus-gh-runner v2.0.0

You are moving the `agentcompute` image builds from GitHub-hosted runners
to ephemeral VMs on the lab's Incus cluster, using `meigma/incus-gh-runner`
v2.0.0 in its HTTPS mode. The first customer of the image pipeline is the
runner VM image itself; the proof is one protected `router` build running
on a lab runner, publishing, and boot-testing on the cluster — with runner
VM nesting still disabled.

## Read first

1. `/Users/josh/code/lab2/AGENTS.md`; Phase 1's `images/README.md` and
   workflows in `agentcompute`; Phase 2's report (the server exists now and
   reconciles the catalog).
2. `/Users/josh/code/lab2/.wt/journal-jmgilman/.journal/019/IMAGE_PIPELINE.md`
   ("CI on the lab" and "The shape that falls out") and `PLAN.md` Phase 4.
3. `meigma/incus-gh-runner` at tag **v2.0.0**, checked out at
   `/Users/josh/code/meigma/incus-gh-runner` (fetch tags): `README.md`,
   `docs/docs/how-to/deploy.md` (HTTPS mode, systemd credentials, the
   `deploy/incus/` CUE baseline and drift validator), `how-to/build-runner-images.md`
   (the guest contract your runner image must implement — read every
   step; the serial console and payload path are load-bearing),
   `reference/configuration.md` (`incus.url`, `client_cert_file`,
   `client_key_file`, `server_cert_file`, project, image, profiles, owner),
   `reference/guest-contract.md`. Note `deploy/incus/` assumes a single
   host (one bridge, one pool) and `validateServer` rejects a cluster
   mismatch — you will hit this.
4. Fleet `cluster/` project conventions (Phase 1/3 touched it) and the
   OpenTofu Incus roots convention in `fleet` for one-off VMs (VISION
   "VM orchestration": OpenTofu owns non-Talos VMs; state in the lab's S3
   bucket).
5. `research/linux-images.md` "Runner sizing" and "Root boundary" notes.

## The spike that comes first

1. Build a **minimal Ubuntu 24.04 server runner image** with distrobuilder
   (`images/runner/distrobuilder.yaml`, VM output, split) implementing the
   guest contract: `incus-agent` generator, Actions Runner under a
   dedicated user with pinned version + SHA, the shipped `guest/` files,
   `ttyS0` console, machine-id reset, growroot, signed shim/GRUB. Two
   variants or one image with a build-time flag: the general
   **untrusted-PR** runner (no sudo) and the **publisher** runner (narrowly
   scoped sudo for distrobuilder: loop devices, mounts, `qemu-img`). Keep
   them separate images if that is simpler; the guide's hardening
   baseline is the floor.
2. Boot-test per the guide's step 10 in a disposable project on the
   cluster (bogus payload → status transitions → poweroff) before
   deploying the controller.
3. Stand up the controller **once, by hand, on `sandbox01`** in HTTPS mode
   against the cluster with a trust certificate restricted to a new
   `github-runners` project, to learn what `deploy/incus/`'s validator
   rejects on a cluster. Do not fight the validator with bypasses.

## Deliverables

- `agentcompute` PR: `images/runner/…` recipe(s), pins, catalog entries,
  the publish workflow extended to build/publish the runner image, and
  the `router` build switched to the publisher scale set by setting the
  existing `IMAGES_RUNNER` repository variable (Phase 1 made `runs-on`
  a variable), on protected refs only. PR validation stays on
  GitHub-hosted runners (untrusted code never reaches the publisher pool).
  While here: skip the build when the release tag already exists, so a
  `master` run on an unchanged tree is a no-op rather than a publish
  failure (Phase 1 finding 5).
- `fleet` PRs: (a) `cluster/` deploy for the `github-runners` project and
  its restricted baseline (project restrictions, profile with
  `security.nesting=false`, `security.secureboot=true`, bridged NIC on
  `fast40` or a NAT'd bridge with controlled egress — follow the
  `deploy/incus/` CUE baseline's intent even where its single-host shape
  does not apply), and the CI trust identity restricted to
  `github-runners` + `image-build`; (b) an OpenTofu root
  `incus/incus-gh-runner/` for the controller VM (Ubuntu, the DEB from
  `pkgs.meigma.dev`, systemd unit with credential drop-ins for the
  GitHub App key and the Incus client key, config pointing at
  `https://10.10.10.14:8443` with the pinned server cert). The controller
  VM is OpenTofu-owned per the one-off-VM decision.
- `meigma/incus-gh-runner` issue (and PR if you can do it cleanly): make
  `deploy/incus/` and `internal/incusvalidate` cluster-aware or
  project-scoped so the drift validator is usable against a cluster.
  Passes the second-user test; do not fork a lab-local copy.
- `GilmanLab/secrets` PR: the GitHub App private key and the Incus client
  key for the controller under the appropriate scope, following the SOPS
  conventions in that repo's README and ADR-0003 (KMS + PGP, scoped
  encryption context).

## Working rules

- `security.nesting` stays `false` on runner VMs. If any build step needs
  KVM, it is being done in the wrong place: move it to the cluster via the
  Incus API.
- The publisher runner's sudo allowlist is explicit and reviewed; no
  `NOPASSWD: ALL`.
- Controller credentials are systemd credentials, never in `config.yaml`,
  never in git plaintext.
- **`GilmanLab/agentcompute` is public.** incus-gh-runner's README
  requires a threat review before a public repository targets a
  self-hosted scale set: fork `pull_request` workflows must never be able
  to select the publisher label. Before enabling the scale set, do the
  review and record it in `images/README.md`: repository settings require
  approval for all outside-collaborator workflow runs; the publisher
  workflow triggers only on `push` to `master` and `workflow_dispatch`
  (never `pull_request`/`pull_request_target`); `IMAGES_RUNNER` is a
  repository variable, which forks cannot read into their own runs;
  `github.runner_group` stays `default` at repository scope with the
  scale set bound to this repository only; confirm with
  `gh api repos/GilmanLab/agentcompute/actions/permissions` and the
  scale-set's repository binding. If any of these cannot be made true,
  stop and report rather than proceeding.
- Do not edit the design documents; report findings.

## Acceptance evidence

- Runner image boot-test transcript per the guide (status file
  `starting` → `running` → terminal, console lifecycle lines, poweroff).
- Controller running as a VM on the cluster (`incus list --project
  default` shows it; `systemctl status incus-gh-runner` inside),
  `journalctl` showing scale-set session established and min-runners
  standby created in `github-runners`.
- One `router` publish job: `runs-on` the scale-set label, job log shows
  the lab runner hostname, distrobuilder ran, boot-test against the
  cluster passed, GHCR digest recorded; runner VM deleted afterward
  (`incus list --project github-runners` empty or at standby count).
- Negative checks: a config with a wrong `server_cert_file` fails to
  connect; with the CI cert, listing instances in the `default` project
  returns an empty list and creating one there fails (restricted
  certificates filter reads and refuse mutations — no 403 on reads).
- Measured: runner VM boot-to-job latency, build wall time vs the
  GitHub-hosted numbers from Phase 1.
- `fleet` dry-runs no-op; OpenTofu plan clean.

Report with findings, including exactly what the drift validator rejected
and what you filed upstream.
