---
title: Deploy private image runners
description: Deploy and qualify the private image publisher and its Incus controller.
---

# Deploy private image runners

Deploy the image publisher for the private `GilmanLab/agentcompute-images`
repository. Recipes, immutable image references, and the catalog remain in
[`GilmanLab/agentcompute`](https://github.com/GilmanLab/agentcompute/tree/master/images).
Do not register a self-hosted runner with that public repository.

## Preconditions

- Administrative access to the Incus cluster, GitHub organization and packages,
  and the lab S3 state bucket.
- An authenticated `lab-admin` AWS profile, plus the repository-pinned tools in
  a trusted, interactive operator shell. Fleet deployment tasks do not run in CI.
- OpenTofu `>= 1.10`, `just`, and the public `images:` Incus remote used to fetch
  the controller VM image.
- Point `INCUS_CONF` at the existing administrator CLI configuration, including
  its client identity and pinned server certificate. On macOS this is usually
  `$HOME/Library/Application Support/incus`; the provider otherwise defaults to
  `$HOME/.config/incus`. Do not enable automatic certificate acceptance.
- Reviewed companion changes in `agentcompute`, `agentcompute-images`, `fleet`,
  and the secrets repository. Keep the private repository out of `init.sh`.
- The guest lifecycle smoke passes for both runner image variants before any
  controller is started.
- Escrow both App private keys and both Incus client keys under the appropriate
  `services/incus-gh-runner/` and `services/agentcompute-images/` scopes. Follow
  [ADR-0003](../decisions/0003-use-kms-with-pgp-recovery-for-secrets.md); use KMS and
  the recovery PGP recipient, not a local-only encrypted copy.

## Safety boundary

The public publisher runs on a GitHub-hosted machine, validates its definitions,
then dispatches a full commit SHA. The private bake checks public-master ancestry
before running source code. The root-owned build wrapper repeats that check in
its own checkout. Neither gate accepts a pull-request branch merely because its
workflow run received approval.

The `agentcompute-publisher` scale set uses the `default` runner group and is
repository-scoped to `agentcompute-images`. The general `runner` image is not
registered with a public pool. All outside contributors require workflow approval
in the public repository, and every action requires a full commit SHA. These
settings supplement repository-scoped runner registration; they do not replace it.

Source maintainers, private workflow maintainers, and the dispatch/catalog App
remain trusted publishers. The publisher VM has an explicit build-wrapper sudo
grant; the general runner has no such grant. Neither image permits nested
virtualization. The controller Incus identity can use only `github-runners`;
CI can use `github-runners` and `image-build`. Neither can read default-project
instances or mutate default-project resources. Jobs reach external services only
through the proxy's hostname allowlist; they also have explicit DNS and Incus API
access.

The private bake does **not** mint the GitHub artifact attestations produced by
the previous public image workflow. Digest verification and boot qualification
are not a substitute for that provenance record. Do not claim that new private
bakes carry the old attestation.

## Prepare GitHub identities

1. Create a dedicated controller App with repository administration-write and
   metadata-read permissions. Install it only on `agentcompute-images`.
2. Create a separate dispatch/catalog App with contents-write and
   pull-requests-write permissions. Install it on the public source repository
   and the private bake repository only. The public workflow requests a
   contents-write token for the private repository; the private catalog step
   requests contents-write and pull-requests-write for the public repository.
3. Set `IMAGES_APP_CLIENT_ID` and the escrowed `IMAGES_APP_PRIVATE_KEY` in both
   repositories. Never reuse the controller App key as an Actions secret.
4. Grant the private repository Actions write access to the existing GHCR
   `agentcompute/router` package. After the first publication creates
   `agentcompute/runner` and `agentcompute/runner-publisher`, verify that access
   on both new packages too. Keep all three packages public: the catalog
   reconciler pulls without registry credentials. Linking a package to the
   public source repository does not make its visibility public or grant the
   private workflow access.
5. Remove `IMAGES_RUNNER` from the public repository. Confirm its runner inventory
   is empty and its publisher triggers only on protected-master pushes or manual
   dispatches. Keep the public `image-publish` environment restricted to protected
   branches.

## Qualify the images

From the source repository on a Linux amd64 build host, validate the pins and
build each runner variant with `images/build.py build --image runner` or
`--image runner-publisher`. Each build requires fresh work and output directories.
The recipe uses a checksummed Ubuntu base and CA bootstrap package, a fixed
Ubuntu snapshot, a checksummed Actions Runner, and the unmodified v2.0.0 guest
files.

Run `images/runner/smoke.py` against a disposable, non-default Incus project with
a `runner-smoke` profile. Supply its split `incus.tar.xz` and `disk.qcow2` files,
remote, project, profile, and evidence directory. The smoke uses a temporary
Linux status observer to capture brief file transitions without changing the
shipped guest implementation. Require:

- An active guest path unit and a grown root filesystem.
- Actions Runner executes as `actions-runner`, and the guest obtains a DHCP
  default route. A root-owned Incus agent responding is not enough.
- Status-file transitions `starting` → `running` → `exited` after a bogus JIT
  payload, and deletion of both payload files.
- Corresponding serial-console lifecycle lines with no JIT payload disclosure.
- Guest-initiated poweroff and deletion of the test VM and any image the smoke
  imported. An existing image is not owned by the smoke and is not deleted.

Capture the serial buffer during the guest's 30-second diagnostics grace period,
not after poweroff: the tested cluster returns an empty post-poweroff VM console.
The smoke stages the zero-byte readiness marker and renames it atomically;
directly pushing the watched filename can race the guest's immediate deletion.

## Converge and deploy

1. Run `moon run fleet-cluster:image-build` with the existing public CI certificate
   in `FLEET_IMAGE_BUILD_CERT_FILE`. This creates the project before the CI trust
   references it, enables bounded VM qualification, and supplies `runner-smoke`
   without changing the router's default profile.
2. Export the two **public** Incus client certificate paths as
   `FLEET_GITHUB_RUNNERS_CONTROLLER_CERT_FILE` and
   `FLEET_GITHUB_RUNNERS_CI_CERT_FILE`. Run
   `moon run fleet-cluster:github-runners` from the fleet repository. The deploy
   owns the restricted project, bridge, ACL, publisher profile, and both trusts.
3. Bootstrap the released v2.0.0 controller once on `sandbox01`, using HTTPS, the
   pinned server certificate, and the restricted controller identity. Require a
   GitHub session and record the unmodified validator's rejection. Keep
   `capacity.min_runners=0` for this spike until the managed proxy is available.
4. Stop the manual controller. Do not run two controllers with the same owner and
   scale set during the move.
5. In fleet's `incus/incus-gh-runner/`, configure the real App identifiers, the
   qualified publisher image, and the public controller certificate path. Check
   address and port conflicts against the
   [address plan](../reference/networking/address-plan.md).
6. Authenticate AWS, export `AWS_PROFILE=lab-admin` and
   `GLAB_AWS_STATE_BUCKET` with the existing lab bucket name, then run
   `just check`, `just init`, and `just plan`. Review the saved plan before
   `just apply`.
7. Wait for cloud-init to complete. Deliver the two private keys using the
   `credential_delivery_commands` OpenTofu output. The packaged systemd credential
   drop-ins load them; private keys must not enter cloud-init, configuration YAML,
   or OpenTofu state.
8. Start the controller and require its GitHub session and standby runner logs.
   Configure the private workflow's restricted CI certificate, key, and server
   pin as `INCUS_CLIENT_CERT`, `INCUS_CLIENT_KEY`, and `INCUS_SERVER_CERT`.

### Controller inputs and credentials

Set these real, non-secret values in the root's `terraform.tfvars`:

| Variable | Value |
| --- | --- |
| `github_app_client_id` | Controller App client ID |
| `github_app_installation_id` | Its private-repository installation ID |
| `runner_image` | Qualified publisher alias or fingerprint imported into `github-runners` |
| `controller_client_certificate_file` | Local path to its public client certificate |

The server pin defaults to fleet's committed `cluster/tls/incus-cluster.crt`.
Verify that fingerprint against the cluster before first use. The provider's
`incus_address` must be the address of the member hosting the controller, not a
round-robin alias: bridge network forwards belong to the member serving the API
request. Keep `controller_address` equal to fleet's
`GITHUB_RUNNERS_PROXY_TARGET_ADDRESS` so same-member post-DNAT traffic matches
the runner ACL.

Bootstrap downloads the official v2.0.0 amd64 DEB, verifies its pinned SHA-256,
installs that exact version, and holds it against unattended upgrades. The
package's GitHub attestation was verified against `meigma/incus-gh-runner`.
The upstream apt example is not usable: its key URL returns 404 and the live
repository does not contain this package. Update `controller_package_version`
and `controller_package_sha256` together after verifying a replacement release.
The unit is enabled but skipped until both credential files exist.
After cloud-init, deliver the App key to
`/etc/incus-gh-runner/github-app-private-key.pem` and the Incus key to
`/etc/incus-gh-runner/client.key`, both `root:root` mode `0600`. systemd's
`LoadCredential=` supplies them to the dynamic service user. Rotation requires
replacing the file and restarting the controller.

The proxy's `proxy_allowed_hosts` permits GitHub/Actions, GHCR, and the specific
Ubuntu, Alpine, Go, and Python download hosts needed by the pinned recipes.
Its source allowlist accounts for both local runner addresses and other members'
NAT addresses. Changes require controller-VM replacement, not an in-place edit
that the next OpenTofu apply cannot reproduce.

## Verify the cutover

A protected-master image change must produce the full chain: hosted validation,
private dispatch, a lab VM running the bake, qualified GHCR releases, a public
catalog digest PR from the dedicated App, and deletion of the completed job VM.
The public dispatch job succeeding is not evidence that the private bake succeeded.

An unchanged definition tree skips assembly and publication. It still fetches
and qualifies existing digests; authentication and registry failures are not
cache misses. Catalog and README changes do not change the definition identity.

Verify a non-master SHA refuses before assembly, an incorrect server pin fails
TLS, both restricted identities return `[]` for default-project instance reads,
and default-project mutations are denied. Record runner startup latency and
per-image wall time; compare router work against the earlier approximately
3.5-minute hosted router workflow, not against a three-image aggregate.

After success, retire the old public image-build CI trust and unused public Incus
secrets. Repeat both fleet dry runs and require no changes, then require a clean
OpenTofu plan. Keep the bake's metrics, lifecycle transcripts, and release JSON.

## Recovery and remaining validation gap

The released v2.0.0 runtime supports clustered HTTPS connections, but its drift
validator does not support this cluster baseline. Track
[upstream issue 68](https://github.com/meigma/incus-gh-runner/issues/68) and
[PR 69](https://github.com/meigma/incus-gh-runner/pull/69). The contribution adds
cluster-member topology checks; the lab's wildcard core listener, shared storage,
and IncusOS IPv6 filtering constraints still require explicit qualification.
Do not install a local validator patch or weaken a check to obtain a passing
result. Until a compatible upstream release is qualified, fleet convergence and
the negative checks above enforce the reviewed baseline.

The lab-specific controls differ from the single-host baseline:

- Each cluster member has its own NAT bridge; the runner project does not own
  those host networks.
- Cluster members also host unrelated workloads. A VM escape would reach a shared
  compute host, not the upstream baseline's dedicated, single-purpose host.
  Project restrictions and network controls do not eliminate that residual risk.
- Runner storage uses a bounded slice of the shared `data` pool rather than a
  dedicated pool.
- IncusOS does not load `br_netfilter`, so enabling `security.ipv6_filtering`
  prevents VM startup. The bridge has no configured IPv6 service. The NIC ACL
  denies IPv6 traffic, including link-local and manually assigned addresses,
  and port isolation prevents same-bridge peers from communicating. Qualify
  this with live peer listeners and explicit neighbors; failed ARP or NDP
  alone is not evidence of packet filtering.
- Incus 7.4 supports project-level VM nesting restrictions. The project blocks
  nesting in addition to the profile's `security.nesting=false`.

The unmodified v2.0.0 validator returned
`clustered Incus is outside this dedicated-host baseline`. The upstream
cluster-member contribution progressed to `core.https_address drift detected`:
the lab listens on `:8443`, whereas that baseline requires an exact member
address. These are failed validation results, not waived checks.

To stop scheduling, stop the controller service first and inspect active jobs
before removing VMs. Do not move publication back onto public self-hosted runners.
For controller configuration changes, drain jobs and explicitly replace the VM:
cloud-init does not rewrite an existing guest. Restore escrowed keys afterward.
Stop the rollout if credential escrow, package permissions, lifecycle qualification,
restricted access, or the private runner boundary cannot be verified.
