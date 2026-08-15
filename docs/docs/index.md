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

## Designs

- [Lab v2 core network design](designs/drafts/lab-v2-core-network.md) defines
  the core topology, device boundaries, configuration requirements, and
  verification criteria.

## Reference

- [Device naming](reference/naming.md) is the canonical registry of device
  names and the rules for assigning them.
- [Hardware inventory](reference/hardware-inventory.md) records every physical
  device in the lab with its model and specifications.
- [Networking hardware](reference/networking/hardware.md) identifies the core
  network devices and their roles.
- [Physical connections](reference/networking/physical-connections.md) records
  every installed cable and its endpoint ports.
