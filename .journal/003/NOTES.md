---
id: 003
title: New session (goal pending)
started: 2026-08-18
---

## 2026-08-18 15:52 — Kickoff
Goal for the session: not yet stated. The user asked to start a new session; the
first substantive request will define the goal.
Current state of the world: `GilmanLab/root` is a meta repository that clones
`GilmanLab/networking` as an ignored independent repository. Session 001 is
closed and delivered the networking repository, its MkDocs toolchain and Pages
deployment, decision 0001 (VyOS owns Layer 3, switches own Layer 2), the
core-network design draft, and the authoritative hardware and physical-connection
references. Session 002 remains in-progress and is untouched by this session.
Open threads from 001: address/VLAN plan, DHCP/DNS/time ownership, config
rendering and deployment tooling, redundancy decision, architecture and runbooks
after implementation, and `docs.gilman.io` DNS verification.
Plan: wait for the user's actual request, then scope work, load task-relevant
skills, and create implementation branches inside the owning repository.

## 2026-08-18 16:05 — Tailscale search in ~/code/lab
Request: locate the Tailscale configuration in `~/code/lab` for migration into
the new lab repos.
Finding: there is no Tailscale implementation in `~/code/lab`. A
case-insensitive search across the whole tree, including gitignored files, and a
full-history filename search (`git log --all --name-only`) returned only:
- `docs/architecture/09_design_decisions/003_vyos_gitops.md` — ADR proposing
  GitHub Actions + Ansible + Tailscale (`tailscale/github-action@v2`,
  `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_SECRET`, `tags: tag:ci`) for VyOS deploys.
- `docs/architecture/09_design_decisions/007_image_pipeline_s3_intermediary.md`
  — Tailscale rejected as the image-transfer path.
- `docs/architecture/11_risks.md`, `docs/architecture/index.md`,
  `docs/architecture/appendices/A_repository_structure.md` — references to
  ADR 003.
- `infra/network/vyos/ansible/inventory/hosts.yml:9` — comment "Connect via
  Tailscale in CI/CD"; host actually comes from `$VYOS_HOST`, default
  `10.0.0.2`.
No `.github/workflows` in `~/code/lab` uses the Tailscale action; no ACL policy
file, no Ansible role, no VyOS `service tailscale` stanza.
Adjacent finding: the only real Tailscale artifacts on this machine are in
`~/code/infra` — `nixos/hosts/tailscale-router/` (NixOS host skeleton whose
configuration.nix ends with "Tailscale configuration will be added in a future
iteration", so no `services.tailscale`) and `secrets/services/tailscale.enc.yaml`
(SOPS/age-encrypted OAuth `client_id`, `client_secret`, and a `tags` list; last
modified 2025-11-16). `~/code/lab_old` and `~/code/homelab` contain no Tailscale
references at all.
Next: confirm with the user what "the Tailscale configuration" means, since
there is nothing executable to port from `~/code/lab`.
