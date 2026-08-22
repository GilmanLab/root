---
id: 011
title: Session opened, goal pending
started: 2026-08-21
---

## 2026-08-21 22:21 — Kickoff
Goal for the session: not yet stated. The user asked only to create a new
session; the actual request is still pending.

Current state of the world:
- Journal root is the `journal/jmgilman` worktree at
  `/Users/josh/code/lab2/.wt/journal-jmgilman` (clean, in sync with origin).
- Meta repo `master` is 1 commit behind `origin/master`.
- Sessions 001–009 are closed; session 010 ("Configure storage and networking
  across the cluster") is `in-progress` and untouched by this session.
- Loaded required skills `git` and `worktrunk`; read `TECH_NOTES.md` and the
  summaries of sessions 007, 008, 009.
- Lab state per `TECH_NOTES.md`: four-node Incus cluster live (`nas01` .14
  leader; `lab01`–`lab03` .11–.13), AMT OOB provisioned on the MS-02s, both
  switches under management, gw01 authoritative for L3/DNS/NTP. Storage and
  the SFP+/10GbE data-network roles remain unassigned (session 010 territory);
  data drives are still blank.

Plan: wait for the user's actual request, then scope the work, load any
task-relevant skills, and follow the sub-repository branch/worktree + PR rules
from `AGENTS.md`.

## 2026-08-21 22:45 — Operations Center / monitoring research + plan
Request: plan how to deploy Operations Center to monitor the lab cluster (T44).

Headline finding: **OC is not a monitoring system and cannot adopt this
cluster.** Two parallel researchers (`history://OpsCenterCaps`,
`history://IncusObservability`) plus local primary sources:
- OC v0.8.1 (2026-08-07, pre-1.0, 40 open issues) = inventory + provisioning +
  update channels + warning ledger; 5-minute reachability poll. No time series,
  no alerting; the released OpenAPI has no metrics surface and the daemon wires
  no `/metrics` handler (confirmed in the local module cache — the
  `*_prometheus_gen.go` middleware is dead code).
- Registration is one-way: `provider_operations_center.go:201` returns
  `ErrDeregistrationUnsupported`. It also transfers OS/app/Secure-Boot update
  resolution to OC, colliding with the pinned-seed model (T25/T26). No
  documented import/adopt path for an already-formed cluster.
- OC deployment itself is easy when wanted: it is an IncusOS *application*
  (one primary app per machine → dedicated appliance), and `incusos-builder`
  already supports the `operations-center` seed section with e2e tests.

Monitoring turned out to be nearly free and needed no node-side change:
- IncusOS ships `prometheus-node-exporter` (localhost:9100) and Incus 7.3 merges
  it into `/1.0/metrics`. Verified live on all four members with the existing
  `bootstrap-admin` cert: HTTP 200, ~3300 `node_*` + ~98 `incus_*` series,
  including `node_zfs_zpool_state`, hwmon temps, disks, systemd, filesystems.
  `core.metrics_address` is NOT required — the existing `core.https_address`
  listener serves it.
- All members present the shared cluster cert (SAN `DNS:nas01.glab.lol` only),
  so scrapers must pin `server_name: nas01.glab.lol` + cluster cert as CA.
- Ran step A0 for real: Docker Prometheus (:9099) + Grafana (:3009) on the
  workstation, config in `/tmp/monspike`. All four targets up; Grafana dashboard
  1860 renders with zero "No data" (nas01: CPU 13.4%, RAM 11.7%/29GiB, 24 cores,
  uptime 1.2d, per-pool filesystems, per-NIC mgmt/fast/fast30). Official Incus
  dashboard 19727 also renders but is instance-centric and thin with one
  container. Gotchas recorded: 19727's datasource placeholder is `${DS_INCUS}`;
  never relabel `instance` (breaks community dashboards).
- Gaps that need a future `/os/1.0` poller: pending-update/`needs_reboot`, SMART
  and degraded-vdev detail, Secure Boot/TPM state, LACP/LLDP link state. Remote
  syslog (`/os/1.0/system/logging`) is unset on all nodes.

Plan written to `.journal/011/OPS_CENTER_AND_MONITORING_PLAN.md`: Track A
(monitoring, start now: A0 done → `mon01` on the cluster via tofu in `fleet` +
metrics-scoped cert via `fleet_cluster` → alerting with an external dead-man's
switch → logs → coverage gaps) and Track B (OC spike, decoupled, run entirely on
`sandbox01` with throwaway IncusOS VMs; never switch a production node's provider
until upstream answers adoption/observation-only registration).

Awaiting Josh's rulings on: scraper placement (`mon01` on-cluster vs. `sandbox01`
plus one firewall rule), container vs. VM for `mon01`, alert delivery target, and
whether the OC spike happens now or after the Talos mgmt cluster.

## 2026-08-21 23:05 — Correction: the ask was a GUI, and it already exists
Josh clarified: he wanted a Proxmox-style GUI over Incus, not time-series
monitoring. That changes the answer, not the research.

- The **built-in Incus web UI is already running on the cluster**:
  `https://10.10.10.14:8443/ui/` returns 200, version `7.3-ui-0.21`, served by
  the IncusOS `incus` application. Verified in a real browser (via a throwaway
  localhost cert-attaching proxy, `/tmp/monspike/uiproxy.ts:8099`): instance list
  (meshcommander/Container/nas01/Running), Cluster members page showing all four
  ONLINE with roles + memory (nas01 4.0/29.8 GiB, labs 2.7/64 GiB), Networking/
  ACLs/IPAM, Storage pools/volumes/buckets/custom ISOs, Images, Profiles,
  Operations, Warnings, Settings, Usage, "Create instance", and a per-node
  **Incus OS** panel (Overview/Applications/Debug/Services/System).
- **OC cannot be that GUI.** Enumerated every `swagger:operation` in v0.8.1:
  inventory (instances, networks, profiles, projects, storage, images) is
  `GET` + `POST …/:resync` only. Mutation exists only for servers (reboot,
  poweroff, evacuate, factory-reset, update, BMC power, system network/storage),
  clusters (create, add/remove servers, update, bulk-update), channels, updates,
  tokens, seeds. No instance create/start/stop/console/snapshot/migrate.
- Two real gaps before the UI is pleasant: (1) browser auth — needs the
  `bootstrap-admin` key as PKCS#12 in the keychain, or OIDC via Zitadel (T36);
  (2) DNS/TLS — the four members share one cert whose only SAN is
  `DNS:nas01.glab.lol`, and that name **does not resolve**: the mirrored
  `glab.lol` zone (Route53 private zone → gw01 CoreDNS) has no A records for any
  lab host. Fix at source in `GilmanLab/aws`.
- The localhost proxy I used for verification is an auth bypass; throwaway only,
  never a lab service.

Plan doc restructured into Track 0 (use the UI you already have) / Track A
(monitoring: history + alerts, still wanted) / Track B (OC as fleet control
plane, T44, unchanged).
