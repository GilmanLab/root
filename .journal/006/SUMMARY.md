---
id: 006
title: Automate and deploy the VyOS gateway
date: 2026-08-18
status: complete
repos_touched: [GilmanLab/root, GilmanLab/networking, GilmanLab/secrets]
related_sessions: [001, 002, 005]
---

## Goal

Finalize the Lab v2 core-network design from live evidence, replace the legacy
VyOS/Ansible model with repository-owned pyinfra automation, and deploy the
accepted configuration safely to `gw01`.

## Outcome

The goal was met. The accepted design, canonical address and physical maps,
operator runbook, networking automation, and encrypted password-hash migration
were squash-merged. The new configuration is live and saved on `gw01` with
`PendingSave=False`; a second full synchronization and live DNS checks passed.

## Key Decisions

- Keep `gw01` as the Layer 3, DHCP, firewall, NAT, DNS, and Tailscale boundary;
  keep the dedicated switches at Layer 2.
- Retain VLAN 10 management, VLAN 40 sandbox/workload, and VLAN 70 OOB; retire
  VLAN 20, the old UM760 bridge, and BGP until a real consumer exists.
- Treat the UM760 as `sandbox01` on VP6630 `eth3`, with a VLAN 40 DHCP
  reservation at `10.10.40.10`, rather than as a cluster node.
- Own one complete `config.boot` template in `GilmanLab/networking` and converge
  it with version-agnostic `pyinfra-vyos` operations; the installed rolling VyOS
  version does not satisfy typed-operation schema gates.
- Keep the whole-config load free of password hashes and OAuth credentials;
  apply the console password hash separately before verification.
- Run authoritative `glab.lol` and recursive forwarding through CoreDNS on
  `gw01`; the native VyOS DNS-forwarding commit hook hung during deployment.
- Require preflight, fresh-process verification, save, and final
  `PendingSave=False` gates. Keep deployment operator-triggered rather than
  automatic on merge.

## Changes

- `GilmanLab/root/docs/docs/designs/lab-v2-core-network.md` - promoted and then
  updated the accepted core-network architecture and deployment model.
- `GilmanLab/root/docs/docs/reference/networking/` - added canonical address,
  VLAN, DHCP, hardware, naming, and physical-connection facts.
- `GilmanLab/root/docs/docs/runbooks/vyos-gateway-deployment.md` - documented
  validation, synchronization, verification, failure handling, and recovery.
- `GilmanLab/networking/vyos/gw01/` - added the complete gateway template and
  CoreDNS/mirror assets.
- `GilmanLab/networking/src/networking_vyos/` - added validation, SOPS loading,
  rendering, locking, pyinfra stage orchestration, redaction, verification, and
  verify-before-save behavior.
- `GilmanLab/networking/tests/`, `pyproject.toml`, `uv.lock`, `moon.yml`, and
  `.github/workflows/ci.yml` - added reproducible tooling and 40 behavioral
  tests with pull-request checks.
- `GilmanLab/secrets/network/vyos/ssh.sops.yaml` - removed the plaintext
  password field and added a SHA-512 crypt password hash without changing the
  scoped SOPS recipients.
- Live `gw01` state - removed PowerDNS, IncusOS artifact serving,
  `bootstrap-k0s`, BGP, VLAN 20, and the former UM760 bridge; installed the
  accepted VLAN, DHCP, firewall, CoreDNS, and Tailscale configuration and saved
  it as the boot configuration.

## Open Threads

- Revoke the former Tailscale OAuth client and rotate the console password/hash.
  An early failed VyOS load printed both secret-bearing values into the local
  controller transcript, so they must be treated as exposed.
- Remove the temporary nftables compatibility-chain preparation when a future
  VyOS image no longer has interface commit hooks that assume those chains
  already exist.
- Consider adding rolling-version typed-operation support and a truthful
  comparison surface upstream in `pyinfra-vyos`; do not duplicate those
  capabilities locally.

## Lessons

- A VyOS whole-config load failure can include the entire candidate in an
  exception. Full-load candidates must not contain reusable credentials or
  password hashes.
- A failed VyOS commit can leave runtime side effects and `PendingSave=True`
  even when the boot configuration is unchanged. Reboot to the known saved
  configuration before retrying instead of bypassing the preflight gate.
- The installed VyOS 2025.11 image has commit-hook behavior not captured by
  static template validation; live verify-before-save and working OOB recovery
  are required controls.

## References

- [GilmanLab/root PR #13](https://github.com/GilmanLab/root/pull/13)
- [GilmanLab/networking PR #7](https://github.com/GilmanLab/networking/pull/7)
- [GilmanLab/secrets PR #22](https://github.com/GilmanLab/secrets/pull/22)
- [GilmanLab/root PR #14](https://github.com/GilmanLab/root/pull/14)
- `.journal/001/SUMMARY.md`
- `.journal/002/VISION.md`
- `.journal/005/SUMMARY.md`
