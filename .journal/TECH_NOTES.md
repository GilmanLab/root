# Technical Notes

## Repository layout

- `GilmanLab/root` is a meta repository. `init.sh` clones
  `GilmanLab/networking` as an ignored independent repository, not a submodule.
- Sub-repository changes use a branch and Worktrunk created inside that child
  repository, followed by a GitHub squash-merge PR.
- The canonical documentation skill is
  `.agents/skills/gilmanlab-documentation/SKILL.md` in the root repository.

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
