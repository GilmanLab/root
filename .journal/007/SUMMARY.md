---
id: 007
title: Build and deploy sandbox01 base automation
date: 2026-08-19
status: complete
repos_touched: [GilmanLab/root, GilmanLab/networking, GilmanLab/secrets, GilmanLab/sandbox]
related_sessions: [002, 003, 005, 006]
---

## Goal

Execute session 002's sandbox setup plan: create a private reset-button pyinfra
repository, converge the existing Ubuntu 26.04 `sandbox01` host, establish
secure Tailscale enrollment and access, and prove the result is repeatable.

## Outcome

The goal was met. `GilmanLab/sandbox` now owns the tested base automation for
`sandbox01`; the live host converged and passed Docker, Podman, Incus,
Tailscale, sudo, and SSH smoke checks. Follow-up work repaired the physical
home-to-lab route and replaced ProxyJump with direct MagicDNS/Tailscale SSH for
routine automation. Six PRs were squash-merged across four repositories.

## Key Decisions

- Use a scoped, non-expiring Tailscale OAuth client to mint single-use,
  preauthorized, non-ephemeral auth keys with a 10-minute TTL only when the host
  is unenrolled; this avoids storing a reusable node key and makes converged
  runs independent of the Tailscale API.
- Keep sshd hardening as an explicit final operation after base convergence;
  validate the candidate with `sshd -t`, remove cloud-init's conflicting
  override, and reload atomically to preserve a recovery boundary.
- Install Incus from Zabbly `stable` for Ubuntu `resolute`, Tailscale from its
  supported `noble` suite, and Docker and Podman from the Ubuntu archive;
  upstream suite availability determined these repository choices.
- Keep Incus deliberately vanilla: one 50 GiB loop-backed ZFS pool, the default
  bridge, and no cluster, projects, monitoring, backups, or durable workloads.
- Repair the tracked `gw01` firewall source instead of masking the failed
  RouterOS health check locally; narrowly allowing ICMP from `10.0.0.1`
  restored the intended physical `10.10.0.0/16` route.
- Use direct MagicDNS `sandbox01` for routine pyinfra transport and derive strict
  SSH host keys from `tailscale status --json`; retain explicit physical host
  and known-hosts overrides only for fresh bootstrap or break-glass access.

## Changes

- `GilmanLab/root/init.sh` - added idempotent cloning of the private
  `GilmanLab/sandbox` repository.
- `GilmanLab/networking/tailscale/policy.hujson` - added `tag:sandbox`, admin tag
  ownership, and Tailscale SSH authorization for the intended users.
- `GilmanLab/networking/vyos/gw01/config.boot.tmpl` - allowed gateway health
  probes from the transit router so RouterOS keeps the physical lab route
  active.
- `GilmanLab/secrets/.sops.yaml` and `sandbox/tailscale.sops.yaml` - added the
  scoped, metadata-validated OAuth enrollment client under the established KMS
  and YubiKey recovery recipients.
- `GilmanLab/sandbox/src/sandbox/` - added CLI configuration, secret loading,
  OAuth key minting, pyinfra inventory and operations, package setup, Incus,
  Docker, Podman, Tailscale enrollment, sudoers management, sshd hardening, and
  direct Tailscale SSH host-key discovery.
- `GilmanLab/sandbox/tests/`, `moon.yml`, `pyproject.toml`, `uv.lock`, and
  `.github/workflows/ci.yml` - added reproducible checks and 27 behavioral tests.
- `GilmanLab/sandbox/README.md` - documented fresh-image reset, routine deploy,
  explicit physical bootstrap and recovery, hardening, validation, and
  idempotence expectations.
- Live `sandbox01` - converged the Ubuntu baseline and runtimes, enrolled the
  host as `tag:sandbox`, installed the managed sudoers and sshd policy, and
  verified both Tailscale and physical recovery paths.

## Open Threads

- Session 002 can proceed with T32 using the now-validated Incus host. No
  opinionated Incus projects, clustering, monitoring, backups, or durable
  workload policy was added in this session.
- The destructive fresh-Ubuntu reset procedure remains documented but was not
  exercised because the user directed convergence of the existing installation.
- The explicit physical deployment override remains required for an unenrolled
  fresh image; accepted Tailscale subnet routes may need to be disabled
  temporarily on the controller for that path.

## Lessons

- Tailscale subnet-route acceptance can hide a broken physical route. Verify the
  selected local route and the upstream router's health-check state before
  attributing an SSH failure to host configuration.
- MagicDNS peers on the same LAN use direct WireGuard transport to the peer's
  physical endpoint; a separate SSH ProxyJump does not improve that path.
- Tailscale's advertised peer SSH keys provide a strict, controller-generated
  known-hosts source without weakening host-key checking or committing a
  mutable host key.

## References

- [GilmanLab/root PR #16](https://github.com/GilmanLab/root/pull/16)
- [GilmanLab/networking PR #9](https://github.com/GilmanLab/networking/pull/9)
- [GilmanLab/networking PR #10](https://github.com/GilmanLab/networking/pull/10)
- [GilmanLab/secrets PR #23](https://github.com/GilmanLab/secrets/pull/23)
- [GilmanLab/sandbox PR #1](https://github.com/GilmanLab/sandbox/pull/1)
- [GilmanLab/sandbox PR #2](https://github.com/GilmanLab/sandbox/pull/2)
- `.journal/002/SANDBOX_SETUP_PLAN.md`
- `.journal/006/SUMMARY.md`
