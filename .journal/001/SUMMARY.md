---
id: 001
title: Design Lab v2 core networking
date: 2026-08-14
status: complete
repos_touched: [GilmanLab/root, GilmanLab/networking]
related_sessions: []
---

## Goal

Establish the Lab v2 core-networking workspace and begin an authoritative design
for the VyOS and switching infrastructure.

## Outcome

The goal was met. `GilmanLab/root` now bootstraps the independent
`GilmanLab/networking` repository and enforces Worktrunk-based sub-repository
work. The networking repository has a reproducible documentation toolchain, a
published MkDocs site, an accepted Layer 2/Layer 3 responsibility decision, a
scoped core-network design, an authoritative hardware reference, and a complete
port-to-port map of the installed cabling.

## Key Decisions

- Keep documentation in the repository that owns the implementation so changes
  can update code, configuration, and documentation together.
- Use Diátaxis for document purpose, MADR 4.0 for decisions, and a lightweight
  Google-style structure for design documents.
- Use VyOS on the VP6630 for Layer 3 gateways, route selection, firewall policy,
  and NAT.
- Use the CRS309-1G-8S+IN for core Layer 2 switching and the TEG-3102WS for
  MS-02 management/OOB switching.
- Use the VP6630 as the management/OOB gateway and policy boundary for the
  TEG-3102WS network.
- Keep the physical connection map separate from VLAN, address, bond, operating-
  system interface, and link-setting configuration.
- Publish only confirmed facts. Omit unknown values until the user verifies
  them.
- Defer architecture and runbook documents until the system is implemented and
  the procedures have been exercised.

## Changes

- `GilmanLab/root/init.sh` and `.gitignore` — clone the networking repository as
  an ignored independent Git repository.
- `GilmanLab/root/AGENTS.md` — require child-local Worktrunk branches and the
  shared documentation convention.
- `GilmanLab/root/.agents/skills/gilmanlab-documentation/` — define repository
  documentation structure, ownership, lifecycle, and decision/design templates.
- `GilmanLab/networking/mise.toml`, `mise.lock`, and `.moon/` — pin the local
  toolchain and configure the Moon workspace.
- `GilmanLab/networking/docs/` — add the uv-managed Material for MkDocs site and
  strict build tasks.
- `GilmanLab/networking/.github/workflows/docs-pages.yml` — build and deploy the
  documentation through GitHub Pages.
- `GilmanLab/networking/docs/docs/decisions/0001-use-vyos-for-layer-3-and-switches-for-layer-2.md`
  — record Layer 3 and Layer 2 ownership.
- `GilmanLab/networking/docs/docs/designs/drafts/lab-v2-core-network.md` — define
  the core topology, invariants, failure boundaries, and verification criteria.
- `GilmanLab/networking/docs/docs/reference/hardware.md` — record authoritative
  device models and roles.
- `GilmanLab/networking/docs/docs/reference/physical-connections.md` — record 18
  installed cables, 36 unique connected endpoints, and two explicitly
  unconnected ports.

## Open Threads

- Define the address plan, VLAN allocation, operating-system interface mapping,
  link settings, and link aggregation.
- Assign DHCP, DNS, and time-service ownership.
- Select and implement configuration rendering, validation, deployment,
  rollback, and drift detection for VyOS and both switches.
- Decide whether the single gateway and switch failure boundaries are accepted
  or require redundancy.
- Add current-state architecture and tested runbooks after implementation.
- Restore or verify DNS for `docs.gilman.io`; GitHub Pages deployments succeeded,
  but the custom domain did not resolve during this session.
- Attach the documented `PHY-001` through `PHY-018` identifiers to the physical
  cables if physical labels are required.

## Lessons

- Historical configuration is useful research evidence but should not appear as
  current design authority.
- Stable physical cabling belongs in a dedicated reference map. Logical network
  configuration can then change without rewriting physical facts.
- Port-to-port documentation needs the chassis label from both endpoints. An
  explicitly unlabeled port is more accurate than an inferred name.

## References

- [GilmanLab/root PR #1](https://github.com/GilmanLab/root/pull/1)
- [GilmanLab/root PR #2](https://github.com/GilmanLab/root/pull/2)
- [GilmanLab/networking PR #1](https://github.com/GilmanLab/networking/pull/1)
- [GilmanLab/networking PR #2](https://github.com/GilmanLab/networking/pull/2)
- [GilmanLab/networking PR #3](https://github.com/GilmanLab/networking/pull/3)
- [GilmanLab/networking PR #4](https://github.com/GilmanLab/networking/pull/4)
- `GilmanLab/root` commits `81756b0` and `9f061a4`
- `GilmanLab/networking` commits `81affcf` and `1bee0c7`
