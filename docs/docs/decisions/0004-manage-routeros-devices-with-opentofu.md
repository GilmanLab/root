---
status: accepted
date: 2026-08-20
---

# ADR-0004: Manage RouterOS Devices with OpenTofu

## Context and Problem Statement

RouterOS configuration consists largely of addressable resources with stable
identities, but manual changes do not provide a reviewed desired state or a
repeatable drift check. Related GilmanLab repositories already establish
OpenTofu and remote-state conventions, while the networking repository's
`networking_vyos` package implements a deployment model specific to VyOS. How
should GilmanLab manage RouterOS devices?

## Decision Drivers

- Represent the RouterOS flat resource model as declarative resources.
- Use the established and actively maintained `terraform-routeros/routeros`
  provider instead of implementing RouterOS discovery and reconciliation.
- Reuse the lab's OpenTofu, S3 state, locking, and operator-command
  conventions.
- Isolate each device's credentials, state, and apply blast radius.
- Preserve a recovery path when RouterOS cannot automatically roll back an API
  change that disconnects management.

## Considered Options

- Manage each RouterOS device in a separate OpenTofu root with the
  `terraform-routeros/routeros` provider.
- Extend the `networking_vyos` pyinfra pattern with a RouterOS sibling package.
- Continue applying RouterOS configuration manually.

## Decision Outcome

Manage RouterOS devices declaratively with OpenTofu and the
`terraform-routeros/routeros` provider. `sw-core01` is the first managed device
and has the root `routeros/sw-core01/` in `GilmanLab/networking`. Manage `rtr01`
and the CCR2004 later as sibling device roots when they enter scope.

Each device root has an independent state key. For `sw-core01`, the key is
`networking/routeros/sw-core01.tfstate`. Shared modules may be introduced only
after multiple roots have demonstrated the same configuration need.

### Consequences

- Good, because RouterOS resources have a reviewable desired state and an
  operator can use a plan to detect drift before a change.
- Good, because the provider supplies RouterOS resource discovery and
  reconciliation rather than a new device-specific implementation.
- Good, because existing OpenTofu backend and locking conventions apply without
  coupling multiple devices to one state file.
- Bad, because RouterOS REST changes have no commit-confirmed rollback. The
  management-path resources must be adopted without changes, an operator must
  download a sensitive export before every apply, and cutovers require
  downloaded backups.
- Bad, because GitHub-hosted runners cannot reach the devices. CI can run only
  offline format and validation checks; operators are responsible for live
  plans and drift detection.
- Bad, because each additional RouterOS device adds a root, state key,
  credential, and certificate lifecycle to operate.

### Confirmation

The implementation conforms to this decision when:

- each managed RouterOS device has one OpenTofu root in
  `GilmanLab/networking/routeros/` and one isolated state key;
- the roots use `terraform-routeros/routeros` and do not use a RouterOS sibling
  of `networking_vyos`;
- the `sw-core01` management bridge, trunk port, VLAN 10 row, management VLAN
  interface, address, and default route are imported without replacement;
- every apply has a downloaded pre-apply export, and each cutover record
  includes a downloaded backup;
- pull-request CI performs offline checks without device credentials or device
  access; and
- an operator runs a live plan before every change and after each RouterOS
  upgrade.

## Pros and Cons of the Options

### OpenTofu with the RouterOS Provider

- Good, because the configuration maps directly to provider resources and
  produces a plan before mutation.
- Good, because per-device roots isolate state and applies.
- Good, because it reuses established S3 backend and locking conventions.
- Bad, because a provider operation that breaks the management path has no
  automatic device-side rollback.
- Bad, because useful plans require live device access.

### Extend the pyinfra Pattern

- Good, because it would resemble the existing `networking_vyos` operator
  workflow.
- Bad, because the VyOS package boundary and candidate-save behavior are
  specific to VyOS.
- Bad, because GilmanLab would have to implement and maintain RouterOS resource
  discovery, diffing, and idempotent mutation already supplied by the provider.

### Manual RouterOS Configuration

- Good, because it requires no state backend or provider.
- Bad, because the intended configuration, review history, and drift are not
  represented as one declarative source.
- Bad, because repeated changes depend on operator command history.

## More Information

See the [Lab v2 core network design](../designs/lab-v2-core-network.md), the
[sw-core01 configuration runbook](../runbooks/sw-core01-configuration.md), and
the [network address and VLAN plan](../reference/networking/address-plan.md).
