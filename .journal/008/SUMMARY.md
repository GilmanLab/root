---
id: 008
title: Bring the lab switches under management
date: 2026-08-20
status: complete
repos_touched: [GilmanLab/root, GilmanLab/networking, GilmanLab/secrets]
related_sessions: [001, 006, 007]
---

## Goal

Close the two remaining core-network gaps: `sw-core01` had never been
reconfigured from its v1 state and had no automation, and `sw-mgmt01` was
correct at Layer 2 but still managed on its factory address with nothing
escrowed. Along the way, fix whatever the work surfaced.

## Outcome

The goal was met. `sw-core01` runs the full v2 configuration and is managed by
an OpenTofu root whose plan is empty against the live device. `sw-mgmt01` was
readdressed to its planned static VLAN 70 address, its VLAN table trimmed to
exactly the address-plan state, and its configuration escrowed. Two surfaced
defects were fixed at source: gw01's input firewall never admitted NTP, and an
unsaved manual gw01 change was retired. Seven PRs merged across three
repositories, all live-verified.

## Key Decisions

- Manage `sw-core01` with OpenTofu (terraform-routeros, REST over a pinned
  device-local CA) rather than extending the pyinfra pattern -> user choice;
  architecture designed by subagent, recorded as ADR-0004. One root per
  device; state in the existing lab bucket.
- The management path is adopt-only: no tofu apply ever modifies `bridge-lab`,
  the trunk port row, the VLAN 10 row, `mgmt-vlan10`, `10.10.10.2/24`, or the
  default route -> RouterOS has no commit-confirmed and REST gets no Safe Mode.
- Users and groups on RouterOS stay runbook-owned -> `svc-tofu` deliberately
  lacks the `policy` permission (self-escalation guard), so tofu cannot manage
  groups; passwords must never enter state.
- Adopt-by-create for `routeros_ip_service` -> the provider's import is broken
  upstream in v1.99.1 (Name-ID importer stores the internal `*HEX` id its
  name-keyed read cannot resolve); create semantics are `/set` on the existing
  service, so this is safe.
- Add NTP (udp/123) only to `MGMT_LOCAL` and `OOB_LOCAL` -> VLAN 70 has no
  internet path at all, so gw01 is its only possible time source; sandbox,
  home, and tailnet keep internet NTP.
- Keep `sw-mgmt01` a hand-managed appliance with documented desired state and
  an escrowed backup -> no CLI/IaC surface exists; its SPA JSON API is good
  enough for scripted operator changes but returns `errCode 0` for malformed
  writes without applying them, so every write must be read back.
- `10.10.10.2` and `10.10.70.2` are static interface addresses, not DHCP
  reservations -> switches must not depend on DHCP from the router they front;
  address plan amended and the dead gw01 reservation removed.

## Changes

- `GilmanLab/networking/routeros/sw-core01/` - new OpenTofu root: provider,
  backend (`networking/routeros/sw-core01.tfstate`), pinned CA cert, bridge,
  ports, VLANs 10/40, mgmt interface/address/DNS/route/NTP, services, identity,
  Justfile (check/init/plan/apply/snapshot), moon `routeros-check` in CI.
- `GilmanLab/networking/vyos/gw01/config.boot.tmpl` - removed the dead
  `sw-core01` DHCP static-mapping; added `Allow NTP` udp/123 rule 60 to
  `MGMT_LOCAL` and `OOB_LOCAL`. Both deployed via the guarded sync.
- `GilmanLab/secrets` - new scope `network-sw-core01` with the `svc-tofu`
  credential; escrowed `sw-mgmt01` post-readdress config backup under
  `network/sw-mgmt01/`.
- `GilmanLab/root/docs` - address-plan static-address amendment; design-doc
  configuration-source paragraphs for both switches; new runbooks
  `sw-core01-configuration.md` and `sw-mgmt01-configuration.md`; ADR-0004;
  vyos runbook note that CI-flagged shells hide `runInCI: false` moon tasks.
- Live `sw-core01` - identity, factory port names with PHY comments, single
  VLAN-filtered bridge (defconf bridge/VLANs 30/50/60/192.168.88.1/24 purged),
  hardened services, `svc-tofu` account, device-local CA + leaf cert, NTP
  synchronized to gw01.
- Live `sw-mgmt01` - static `10.10.70.2/24` on VLAN 70, gateway `10.10.70.1`;
  VLAN 1 trimmed to unused SFP slots/LAG placeholders; saved.
- Live `gw01` - NTP firewall rules; unsaved manual eth3 escape-hatch address
  retired (re-add documented in the sw-mgmt01 runbook).

## Open Threads

- Rotate the `sw-core01` `admin` password and store it as `admin_password` in
  `network/sw-core01/terraform.sops.yaml`; deliberately not done by the agent
  to keep break-glass out of transcripts. The `svc-tofu` password transited
  the local session transcript (accepted; rotate at will per runbook).
- v1-era public certs `glab-root-ca`/`glab-intermediate-ca` remain on
  `sw-core01` (harmless); keep-or-remove ruling pending.
- Candidate upstream issue: terraform-routeros `routeros_ip_service` import
  defect (v1.99.1).
- When a device-PKI intermediate exists, migrate the pinned self-signed CA to
  it (ADR-0004/architecture fallback path).
- The TEG-3102WS API upload endpoints (`cfg_upload`) are documented but
  untested; restore has only been proven via the web UI flow.
- gw01's sw-mgmt01 escape hatch (`eth3 192.168.10.5/24`) is gone from running
  config; factory access now requires re-adding it manually (documented).

## Lessons

- RouterOS REST authenticates internally via the binary api layer: a REST-only
  service account needs the `api` policy even with the api service disabled.
- RouterOS 7.16 cannot self-sign a leaf certificate ("CA not found"); mint a
  device-local CA and sign the leaf with it. RouterOS REST rejects
  percent-encoded `*` in item paths — send literal asterisks.
- Moon excludes `runInCI: false` tasks from `moon run` whenever `CI` is truthy;
  agent shells export `CI=true`, so operator tasks need `CI= moon run ...`.
- The TEG-3102WS "binary" backup is a ustar archive containing plaintext CLI
  config — diffable, and its SPA JSON API makes the device scriptable despite
  having no official automation surface.

## References

- [networking#11](https://github.com/GilmanLab/networking/pull/11) sw-core01 tofu root
- [networking#12](https://github.com/GilmanLab/networking/pull/12) gw01 NTP firewall
- [secrets#27](https://github.com/GilmanLab/secrets/pull/27) svc-tofu credential
- [secrets#28](https://github.com/GilmanLab/secrets/pull/28) sw-mgmt01 backup escrow
- [root#19](https://github.com/GilmanLab/root/pull/19) sw-core01 docs + ADR-0004
- [root#20](https://github.com/GilmanLab/root/pull/20) vyos runbook CI note
- [root#21](https://github.com/GilmanLab/root/pull/21) sw-mgmt01 runbook
- `.journal/008/SW_CORE01_TOFU_ARCH.md` (architecture artifact)
- `.journal/006/SUMMARY.md`, `.journal/007/SUMMARY.md`
