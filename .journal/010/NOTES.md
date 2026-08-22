---
id: 010
title: New lab work session
started: 2026-08-21
---

## 2026-08-21 17:25 — Kickoff
Goal for the session: not yet stated; the user asked to start a new session and
will provide the actual request next.
Current state of the world: session 009 closed today with the four-node Incus
cluster live (nas01 leader; lab01/lab02 voters; lab03 standby), AMT provisioned
on all three MS-02s, recovery keys escrowed, and the commissioning runbook
merged (root#22). Open threads from 009: T44 (Operations Center spike), T45
(PiKVM default creds), T46 (secrets checkout consolidation), T47
(meshcommander disposition), storage/workload network design pending (T19
deferred).
Plan: await the user's request, then update this entry with the concrete goal.

## 2026-08-21 17:35 — Goal stated + live survey
Goal: configure storage and networking correctly across all four cluster
nodes (nas01 + lab01–03), starting with nas01.
Live survey (via nas01: remote, bootstrap-admin):
- Cluster: 4 nodes ONLINE (nas01 leader; lab01/02 database; lab03 standby).
- Storage: only `local` zfs pool per node on the OS drive (nas01 usable
  ~91GB). nas01 data drives blank: 2x WD_BLACK SN7100 1TB (nvme0n1/nvme1n1).
  lab01: blank Samsung 990 EVO Plus 2TB. Scrub schedule preset `0 4 * * 0`.
- Network: every node has a single `mgmt` interface (roles
  management+cluster) on VLAN 10, linked at 2.5G through sw-mgmt01. Fast
  links all UNCONFIGURED and link-down: nas01 eno1 10GbE (38:05:25:37:8d:7b,
  sw-core01 port 7), lab01 eno1np0/eno2np1 E810-XXV 25G (…:32:de:f3/f4,
  sw-core01 ports 1–2). Only network: default NAT incusbr0.
- sw-core01 ports 1–7 awaiting role assignment per address plan (docs say
  membership comes with the compute-network design = this session).
Next: put design options to Josh (nas01 pool layout, WD Reds/T19 timing,
LACP vs single link, L2-only cluster/storage VLAN).

## 2026-08-21 18:05 — Design settled (Josh rulings + research)
Josh ruled: SN7100s = zfs mirror; LACP bond both lab SFP+; VLAN 30
10.10.30.0/24 L2-only; HDD reality = 4x 6TB WD Red Pro waiting (5th later)
— VISION's "5x 3TB" is stale, fix at close.
Research (subagents, cited in agent://IncusOsStorage + agent://IncusOsNetwork):
- Storage: PUT /os/1.0/system/storage (full config replace; keep
  scrub_schedule). Types zfs-raid0/1/10/raidz1/2/3. raidz1 4→5 expansion
  SUPPORTED (one device per resilver; ZFS 2.4.3). :wipe-drive endpoint for
  dirty disks. Per-pool recovery keys in GET /system/security
  state.pool_recovery_keys; global retrieved flag resets on pool create →
  re-escrow + POST :retrieved. Incus consumption: :create-volume use=incus,
  then per-member incus storage create --target M data zfs source=<pool>/incus
  + final untargeted create. Cluster pools MUST exist on every member →
  nas01-only HDD Incus pool unsupported; HDD stays OS-level until T16.
- Network: bonds[] mode 802.3ad (LACP fast, layer3+4 hash); vlans[] object
  with parent=bond/iface name, id, addresses. PUT is FULL REPLACE — include
  mgmt verbatim + dns/time/proxy; always set confirmation_timeout, then POST
  /system/network/:confirm. Roles today: storage=no-op, cluster=OVN encap
  default only. Incus cluster.https_address CANNOT move live (offline
  admin cluster edit on all members, appliance entry point UNVERIFIED).
- DECISION: keep cluster raft/API/migration on VLAN 10; VLAN 30 = storage +
  future instance traffic on bonds/10G. No gw01 changes. MTU 1500 (no jumbo).
- DECISION: HDD pool = raidz1 4-wide (~18TB), expand to 5 when drive arrives.
- Pools named: `data` (per-node NVMe), `hdd` (nas01 bulk). Incus cluster pool
  `data` across all 4 members.
Next: create nas01 data mirror → escrow → incus wiring; then sw-core01 tofu
(VLAN 30 + 3 LAGs); then node network PUTs; labs; WD Red install when Josh
is at the rack.

## 2026-08-21 18:40 — Course correction: automation-first (Josh)
Josh interrupted after the ad-hoc nas01 data-pool PUT: all cluster config
MUST be reproducible via pyinfra-incus (sandbox = the pattern example); no
ad-hoc commands. Pool stays live; automation adopts it (same spec → no-op).
Findings: pyinfra-incus==0.2.0 is Josh's own meigma/pyinfra-incus (also
meigma/pyinfra-vyos, template-pyinfra). Gaps for this work: storage_pool op
has no cluster --target support; nothing covers /os/1.0 system APIs. Fill
lab-side in fleet_cluster (package style: fact → validate → diff → noop/CLI),
promote upstream later per T26 lab-first flow.
Repo home: Josh challenged new-repo recommendation; revised ruling = FLEET
(its README already reserved runtime-config ownership, originally imagined
as tofu roots). Fleet = full lifecycle owner of bare-metal nodes: day-0
seeds + day-2 pyinfra convergence; avoids seed↔runtime drift across repos.
Execution model: @local connector, incus CLI against authenticated nas01:
remote (IncusOS has no SSH). Escrow stays a runbook step; deploys assert
the retrieved flag (fails convergence until keys escrowed+acked).
Dispatched: FleetCluster programmer (fleet/.wt/feat-cluster-automation,
cluster/ pyinfra project) + SwCoreVlan30 programmer
(networking/.wt/feat-sw-core01-vlan30-lags, 3x LACP LAG + VLAN 30 tagged
bonds+port7; enslave-vs-bridge-port ordering hazard flagged).
sw-core01 stays tofu (ADR-0004 surface unchanged).

## 2026-08-21 19:30 — Build phase complete
SwCoreVlan30 done (networking 56590d4): 3x 802.3ad bonds (layer-3-and-4,
lacp_rate 1sec), bond bridge ports admit-only-tagged, VLAN 30 tagged on
bonds + port 7 (NOT bridge, NOT port 8). Two-step apply REQUIRED: tofu
cannot order orphaned bridge-port destroys before bond creates (provider
DefaultCreate + parallel graph walk) → step 1 targeted destroy of six
bridge-port rows, step 2 full apply (7 add). Mgmt path untouched.
FleetCluster agent ran out mid-fix; I finished: incus query has NO stdin
form (-d/--data is literal; @- not special) → payloads now literal
QuoteStringed --data argv (non-secret by contract). Hardened: projection
never includes the `local` OS pool in storage PUTs (omission proven safe
live); network op refuses full-replace PUT when current config lacks mgmt.
Storage deploy rephased: all pools+volumes, then all escrow asserts (one
escrow round-trip). fleet f29b403+cfd2d00: cluster/ pyinfra project, 28
behavioral tests, ruff/mypy clean, moon fleet-cluster lane in CI,
SystemSecurity fact strips key material from fact data.
Next: sw-core01 two-step apply, storage deploy, escrow, network deploy.
