---
id: 006
title: New session (goal pending)
started: 2026-08-18
---

## 2026-08-18 19:18 — Kickoff
Goal for the session: Start a new session; the substantive goal has not been stated yet.
Current state of the world: The personal journal is initialized on `journal/jmgilman`, and sessions 003–005 are closed with their durable context captured in `TECH_NOTES.md`.
Plan: Record the developer's first substantive request, inspect the relevant repository state, and execute it through the required isolated worktree and verification workflow.

## 2026-08-18 19:21 — Vision context loaded
Read session 002's `VISION.md` in full. It is background context only, not the assignment for session 006. Retain its confidence labels: rely on `[DECIDED]`, treat `[PROVISIONAL]` as changeable, and do not fill `[OPEN]` items by assumption.

## 2026-08-18 19:35 — Legacy VyOS audit
Compared the central core-network draft and VISION against `~/code/glab/infra/network/vyos/configs/gateway.conf`, then queried `gw01` read-only for interfaces, routes, firewall state, DHCP leases, containers, BGP, hostname, and DNS behavior.

The legacy substrate is reusable: `10.0.0.0/30` routed transit, the `10.10.0.0/16` lab envelope, VLAN 10 management, VLAN 40 workload reservation, VLAN 70 OOB, VyOS-owned gateways/NAT, Tailscale route advertisement, and the `glab.lol` DNS mirror all align with current direction. It is not reusable verbatim. VLAN 20/Tinkerbell, the UM760 bridge and BGP peers, persistent IncusOS artifact serving, live `bootstrap-k0s`, and hostname `gateway` are v1 state that conflicts with settled v2 decisions. The management-switch uplink is still described/configured as the UM760 link and does not carry VLAN 70, while the firewall is attached only to `eth0`, leaving inter-VLAN forwarding and non-`eth0` router input accepted by default.

Recommendation: retain the address envelope and proven transit, explicitly decide the surviving VLANs and network-service owners, write one canonical address/VLAN/port-membership reference, rework firewall attachments and stale services, then update and promote the core-network design. The current draft explicitly excludes the exact address/VLAN facts required to seed IncusOS nodes.

## 2026-08-18 19:58 — Core network design accepted
Josh confirmed the gateway removals (PowerDNS, IncusOS artifact serving, and `bootstrap-k0s`), removal of all BGP until a real consumer exists, separate management and OOB VLANs, DHCP reservations instead of seed-static addresses, and `gw01` ownership of cold-start DHCP and DNS. The UM760 is now the general-purpose `sandbox01`, not a cluster member.

Official MINISFORUM specifications and the rear-panel image confirm that each MS-02 upper RJ45 port is 10GbE management and the lower RJ45 port is 2.5GbE with vPro/AMT. Read-only VP6630 link inspection plus the installed cabling maps `Port 1`/`eth3` to `sandbox01`, `Port 2`/`eth2` to `sw-mgmt01`, `Port 3`/`eth4` to `pikvm01`, and `Port 4`/`eth5` to `kvm01`; `eth4` is therefore not the sandbox link.

Root PR #13 (`docs(networking): finalize core network design`) merged as `b600901`. It promoted the design to accepted, added the canonical address/VLAN/DHCP/interface/switch-port reference, assigned `sandbox01` to VLAN 40 at `10.10.40.10`, retained VLAN 10 management and VLAN 70 OOB, retired VLAN 20, corrected the hardware and physical references, and updated site navigation. Local strict docs build and GitHub Pages build both passed.

## 2026-08-18 20:11 — pyinfra-vyos integration review
Reviewed `meigma/pyinfra-vyos` 0.1.0, its public facts and operations, session serialization contract, secret-handling constraints, and appliance tests. A read-only live probe over the existing SSH path successfully returned `VyOS 2025.11` and `PendingSave=False` from `gw01`.

Recommended using one tracked full `config.boot` template and `config_load(..., save=False)` rather than reproducing the gateway tree through typed operations. The operator workflow should render SOPS values only in memory, stage non-secret CoreDNS assets with ordinary pyinfra operations, commit without saving, run verification in a separate pyinfra process, and call `config_save()` only after all checks pass. A failed verification leaves the prior boot config intact for reboot recovery. Initial execution should remain operator-triggered from the networking repository, not automatic on merge.

The integration needs an exact `pyinfra-vyos==0.1.0` dependency with `uv.lock`, strict SSH host-key verification, a single-host execution lock, redacted fact use, and a companion secrets change replacing the current plaintext VyOS password field with an encrypted password hash. The package intentionally does not provide a truthful read-only whole-config diff; do not invent one locally. Treat synchronization as convergence and add comparison support upstream if it becomes necessary.

## 2026-08-18 22:31 — VyOS automation deployed

Implemented, deployed, and merged the accepted `gw01` configuration across three repositories. Networking PR #7 merged as `84c7010`, secrets PR #22 merged as `351c15e`, and root documentation PR #14 merged as `8232d36`. The implementation worktrees were removed after merge.

`GilmanLab/networking` now owns a locked Python/pyinfra synchronization command, the complete tracked VyOS template, CoreDNS assets, strict SSH handling, redacted facts, preflight and post-save state gates, and verify-before-save orchestration. The SOPS-backed password hash is applied separately with version-agnostic `config()` after the secret-free whole-config load. This prevents whole-config load errors from including the hash. The rolling VyOS 2025.11 image also requires empty nftables compatibility chains before interface commit hooks run.

CoreDNS on `gw01` now owns both the mirrored `glab.lol` zone and recursive forwarding on the VLAN gateway addresses. This replaced native VyOS DNS forwarding after its commit hook hung while waiting on `vyos-hostsd`. The accepted network state removed PowerDNS, IncusOS artifact serving, `bootstrap-k0s`, BGP, VLAN 20, and the old UM760 bridge; retained VLANs 10, 40, and 70; and preserved Tailscale state without retaining `TS_AUTHKEY` in device configuration.

Verification passed: 40 networking tests, formatting, lint, typing, template validation, two complete live syncs, `PendingSave=False`, redaction assertions, authoritative `glab.lol` resolution, recursive public DNS resolution, strict documentation build, and all three pull-request checks.

Open security follow-up: an early VyOS load failure included the former Tailscale OAuth client secret and the current password hash in controller transcript output. The router no longer stores the OAuth secret, and facts now mask both values, but the OAuth client must be revoked and the console password hash must be rotated because both values should be treated as exposed.

## 2026-08-19 09:58 — Close

Session complete. Root PRs [#13](https://github.com/GilmanLab/root/pull/13) and [#14](https://github.com/GilmanLab/root/pull/14), networking PR [#7](https://github.com/GilmanLab/networking/pull/7), and secrets PR [#22](https://github.com/GilmanLab/secrets/pull/22) are squash-merged. Local `master` branches for all three repositories were fast-forwarded and the implementation worktrees were removed.

The accepted configuration is live and saved on `gw01`; a second full synchronization, `PendingSave=False`, redaction checks, and authoritative and recursive DNS checks passed. Remaining security handoff: revoke the exposed Tailscale node-registration OAuth client and rotate the exposed console password/hash.
