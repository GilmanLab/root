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

- The networking repository uses mise, Moon, uv, Material for MkDocs, and a
  strict MkDocs build. Run `mise exec -- moon run docs:build --summary minimal`.
- GitHub Pages deploys from `.github/workflows/docs-pages.yml`.
- GitHub Pages deployments succeed, but `docs.gilman.io` did not resolve during
  session 001.
