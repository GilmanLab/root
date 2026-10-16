---
status: accepted
date: 2026-10-16
decision-makers:
  - Josh Gilman
---

# ADR-0007: Expose the nas01 HDDs as a Clustered Bulk Pool

## Context and Problem Statement

`nas01` carries the `hdd` zpool (4x 6 TB raidz1), but it was OS-level only:
Incus storage pools in a cluster must exist on every member, and the HDDs
exist only on `nas01`. The media stack is the first workload that needs those
disks. How should instances on `nas01` consume the HDD pool?

## Decision Drivers

- Instances get the HDDs through normal Incus custom volumes (quotas,
  snapshots, OpenTofu ownership), not ad-hoc host paths.
- Nothing intended for the HDDs may land on lab SSDs by accident.
- Converged by fleet's `cluster/` project like every other pool.

## Considered Options

- Clustered pool with per-member sources: `nas01` uses `hdd/bulk`, every
  other member a quota-capped placeholder on its `data` pool.
- Host-path or virtiofs passthrough of an `hdd` dataset into one VM.
- Defer until the object-storage design (T16).

## Decision Outcome

Chosen option: **clustered pool with per-member sources**. The Incus pool
`bulk` is a ZFS pool whose `source` is `hdd/bulk` on `nas01` and a 1 GiB
quota-capped `data/bulk` dataset on each lab member. Volumes and instances
that use `bulk` are pinned to `nas01`.

### Consequences

- Good, because consumers use ordinary Incus volumes, so OpenTofu owns them
  and they survive instance rebuilds.
- Good, because a volume accidentally targeted at a lab member fails at 1 GiB
  instead of silently consuming SSD.
- Bad, because `incus storage list` shows `bulk` on lab members that have no
  real capacity behind it.
- Neutral: this does not settle object storage or backup (T16); a future
  Garage deployment can still consume `bulk` volumes.

### Confirmation

`incus storage info nas01:bulk --target nas01` reports the raidz1 capacity,
and `--target lab01` reports 1 GiB. Fleet's
`test_bulk_pool_lands_on_hdd_only_on_nas01` pins the member mapping.

## More Information

- Implementation: `GilmanLab/fleet` `cluster/src/fleet_cluster/deploys/storage.py`
- First consumer: [Deploy and operate the media stack](../runbooks/media-stack.md)
