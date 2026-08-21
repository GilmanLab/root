---
title: GilmanLab
slug: /
description: Centralized documentation for GilmanLab.
---

# GilmanLab

This site is the single documentation home for GilmanLab. Implementation lives
in the owning repositories; every decision record, design, reference document,
and runbook lives here.

## Decisions

- [ADR-0001: Use VyOS for Layer 3 and Dedicated Switches for Layer 2](decisions/0001-use-vyos-for-layer-3-and-switches-for-layer-2.md)
  assigns core routing and switching responsibilities.
- [ADR-0002: Manage the Tailnet Policy File with GitOps](decisions/0002-manage-tailscale-policy-with-gitops.md)
  makes git the source of truth for the tailnet policy file.
- [ADR-0003: Use AWS KMS with PGP Recovery for Secrets](decisions/0003-use-kms-with-pgp-recovery-for-secrets.md)
  uses scoped KMS access for routine decryption and a YubiKey-backed PGP key
  for recovery outside AWS.

## Designs

- [Lab v2 core network design](designs/lab-v2-core-network.md) defines the
  accepted topology, device boundaries, network services, migration, and
  verification criteria.

## Reference

- [Device naming](reference/naming.md) is the canonical registry of device
  names and the rules for assigning them.
- [Hardware inventory](reference/hardware-inventory.md) records every physical
  device in the lab with its model and specifications.
- [Networking hardware](reference/networking/hardware.md) identifies the core
  network devices and their roles.
- [Network address and VLAN plan](reference/networking/address-plan.md) is the
  canonical source for routed prefixes, VLANs, address allocations, gateway
  interfaces, and switch port roles.
- [Physical connections](reference/networking/physical-connections.md) records
  every installed cable and its endpoint ports.
- [Tailscale policy](reference/networking/tailscale-policy.md) records the
  tailnet identity, tags, auto-approved routes, and sync credentials.

## Runbooks

- [Change the Tailscale policy](runbooks/tailscale-policy-change.md) covers
  changing, verifying, reverting, and emergency-editing the tailnet policy.
- [Rebuild nas01](runbooks/rebuild-nas01.md) reinstalls IncusOS on `nas01`
  from git-defined install media and restores it as the cluster bootstrap
  node.
- [Deploy the VyOS gateway configuration](runbooks/vyos-gateway-deployment.md)
  covers validation, inspection, guarded deployment, verification, and
  console recovery for `gw01`.
