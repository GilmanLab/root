# Technical Notes

## Repository layout

- `GilmanLab/root` is a meta repository. `init.sh` clones
  `GilmanLab/networking` and private `GilmanLab/aws` as ignored independent
  repositories, not submodules.
- Sub-repository changes use a branch and Worktrunk created inside that child
  repository, followed by a GitHub squash-merge PR.
- The canonical documentation skill is
  `.agents/skills/gilmanlab-documentation/SKILL.md` in the root repository.

## AWS substrate

- Private `GilmanLab/aws` is the sole writer for six OpenTofu roots:
  `aws/lab-foundation`, `aws/github-oidc`, `network/tailscale`,
  `security/pki/root-ca`, `aws/subnet-router`, and `aws/keycloak`.
  `GilmanLab/infra` no longer contains or writes these roots.
- The lab account is `186067932323` in `us-west-2`, operated with profile
  `lab-admin`. Its manually bootstrapped state bucket is
  `glab-lab-tfstate-186067932323`; state keys remained stable through the move.
- Identity-critical resources include SOPS KMS key
  `2aba1d94-6eaf-4d80-8d26-2077f32fd7c5`, root-CA KMS key
  `5b585512-8604-43ce-b416-90fbd3cffcfa`, private zone
  `Z009084217D5KKVQERJY3`, subnet router `i-07878bb4aa9896dd4`, and Keycloak
  instance `i-069f5e943c6e11092` with volume `vol-09baa3d716d956887`.
- The old-account `s3://gilmanlab-tfstate/network/tailscale.tfstate` remains
  only for the migration rollback window. Delete it explicitly afterward, but
  never read, copy, or delete that bucket's similarly named
  `security/pki/root-ca.tfstate`, which belongs to a destroyed old key.
- Keycloak stays live until Zitadel serves. Its normal OpenTofu plan is clean;
  a refresh-only plan observes provider-computed EBS attachment metadata and
  should not be applied merely to silence migration drift.

## Secrets root of trust

- Private `GilmanLab/secrets` uses one SOPS key group per file containing
  scoped AWS KMS and YubiKey-backed PGP as alternative recipients. Routine
  access uses KMS key `2aba1d94-6eaf-4d80-8d26-2077f32fd7c5`; break-glass
  recovery uses exact Curve25519 encryption subkey
  `51098F038D5D9F84FE342036858A466C85A0979C!` from primary identity
  `3965F16E293466CFE77D47F38C15553EEB22DB2A`.
- Every KMS recipient requires encryption context `Repo: GilmanLab/secrets`
  plus `Scope: <access-boundary>`. An unconditioned consumer grant spans every
  scope and is a defect. Future IAM roles belong in `GilmanLab/aws` and are
  created only for real workflows.
- Secret domains are `fleet/<node>/`, future `clusters/<name>/`,
  `services/<service>/`, and `network/`; legacy `compute/` remains frozen.
  Generated but durable recovery material belongs in the encrypted repository;
  ephemeral runtime-generated secrets do not.
- `GilmanLab/secrets/scripts/check_sops_metadata.py` validates recipients and
  encryption context in CI without decryption. PGP recovery must still be
  tested periodically with a YubiKey and AWS credentials absent.

## Network authority

- The VP6630 runs VyOS and owns Layer 3 gateways, routing, firewall policy, and
  NAT.
- The MikroTik CRS309-1G-8S+IN carries core Layer 2 VLAN traffic.
- The TRENDnet TEG-3102WS connects both non-SFP NICs from each MS-02 for
  management/OOB traffic and uplinks directly to the VP6630.
- The VP6630 provides the management/OOB Layer 3 gateway and firewall policy.
- The MikroTik CCR2004 connects the lab to the home network and internet.
- `networking/docs/docs/reference/physical-connections.md` is the authoritative
  port-to-port map: 18 cables, 36 unique connected endpoints, and two explicitly
  unconnected ports.
- Do not import historical or unverified values into authoritative documents.
  Ask the user to verify missing facts or omit them.

## Documentation tooling

- The meta repository hosts the only MkDocs site, at `docs/`, with a strict
  build. Run `mise exec -- moon run docs:build --summary minimal`. The
  networking repository no longer has a docs tree; an untracked leftover
  `docs/` directory may still sit in its checkout.
- GitHub Pages deploys from `.github/workflows/docs-pages.yml`.
- GitHub Pages deployments succeed, but `docs.gilman.io` did not resolve during
  session 001.

## Tailscale policy

- The tailnet policy file is version controlled at
  `GilmanLab/networking/tailscale/policy.hujson` and applied by
  `.github/workflows/tailscale-acl.yml`: `test` on pull requests, `apply` on
  push to `master` and manual dispatch. Never edit the policy in the admin
  console; the next apply overwrites it.
- Tailnet ID `THZctfF8wr11CNTRL`. The workflow reads repository *variables*
  `TS_TAILNET`, `TS_POLICY_CLIENT_ID`, and `TS_POLICY_AUDIENCE`; none is secret.
- CI authenticates with a Tailscale OIDC trust credential (workload identity
  federation), scopes `policy_file` plus `devices:posture_attributes` and
  `devices:core:read`. No long-lived Tailscale credential exists in CI.
- GitHub issues immutable OIDC subjects for this organization, for example
  `repo:GilmanLab@66194346/networking@1334494603:ref:refs/heads/master`. Trust
  credential subjects must use that numeric form; a name-based pattern fails the
  token exchange with HTTP 403.
- `gitops-pusher` drift detection is inert in ephemeral CI because its
  `--cache-file` etag cache is never persisted. The admin-console lock is the
  real control.
- The SOPS-encrypted Tailscale OAuth client in `~/code/infra` is a
  node-registration credential and must not be reused for policy work.
