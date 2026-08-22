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

## 2026-08-21 20:40 — Converge: storage DONE, VLAN 30 blocked on RouterOS bug
Storage converged end-to-end via fleet-cluster deploy: data pools all 4
nodes (nas01 adopted), incus volumes, keys escrowed (secrets#34, hash-
verified, no transcript exposure), :retrieved acked x4, cluster pool
`data` CREATED on all members. Full rerun = 100% no-change (idempotence
proven). Container smoke on pool data OK.
sw-core01 applied (two-step: 6 destroy, then 7 add; post-plan clean).
LACP flapped: hosts send 1 LACPDU/30s (slow) despite research claiming
IncusOS emits fast → switched bonds to lacp_rate=30secs (e221db2); all 3
bonds stable, both ports active, partner IDs = host bond MACs.
Network deploy converged all 4 nodes (fast/fast30, 10G links up,
addresses correct, confirm flow worked).
BUT: VLAN 30 data path DEAD through the bonds, both directions. Isolation
(macvlan containers, switch counters, sniffer, MAC table): nas01 via
plain port7 works (MAC learned, TX/RX fine); lab frames REACH the switch
ports (counters) but NEVER bridge — under admit-all, pvid 30, ingress
filtering off, hw=no, single-link, post-reboot, post-port-bounce.
LACPDUs process fine. Verdict: RouterOS 7.16.2 bond-as-bridge-port
datapath defect on 98DX8216; changelogs 7.17-7.19 fix a family of
98DX bond+bridge bugs (7.19: "multicast packet flow on hw offloaded
bridge with bonded interfaces"). Diagnostics reverted; switch clean vs
committed config. Test containers v30a/v30b/vlan30test still on pool
data for retest. Decision for Josh: upgrade RouterOS vs single-link now.

## 2026-08-21 21:20 — PRs merged, docs and tracker updated
Merged: fleet#3 (cluster/ project + seed sync — seeds now mirror runtime
fast/fast30; CI green incl. new Cluster checks lane + pinned-builder seed
validation), networking#14 (VLAN 30 + LAGs + lacp_rate fix), root#23
(address plan VLAN 30 + hosts storage column + sw-core01 LAG port roles;
design doc amended: LAGs, storage VLAN, fleet cluster/ as config source;
strict build clean). secrets#34 merged earlier. All worktrees removed.
VISION updated: storage section implementation status + corrected WD Red
inventory (4x 6TB Pro), T12 resolved, T19 rewritten (raidz1 ruling), new
T48 (RouterOS bond-bridge defect decision) + T49 (upstream pyinfra-incus
promotion).
Remaining: T48 ruling from Josh (RouterOS upgrade vs single-link), WD Red
physical install (blocked on rack access). Test containers
v30a/v30b/vlan30test parked on nas01/lab01 pool `data` for the T48 retest
— delete after verification.

## 2026-08-21 22:30 — ROOT CAUSE: LACP mux never converges (E810 ↔ RouterOS)
Josh ruled: upgrade. Done — RouterOS 7.16.2 → 7.24 + RouterBOOT 7.24
(snapshot escrandowed locally /tmp/sw-core01-pre-upgrade-7162.rsc; post-
upgrade tofu plan clean; bonds re-formed). Datapath STILL dead.
Further isolation: lab01 NIC member rx = 0 during nas01-side floods
(switch never distributes); STP forwarding; CPU path dead on 7.24 too;
switch-chip port layer clean. monitor-slaves is the smoking gun:
switch actor flags A-GS---- (Sync, never Collecting/Distributing);
host partner-flags ATG---F- (DEFAULTED — host receives NO switch
LACPDUs; requests fast). Both muxes correctly refuse to open the data
path per 802.3ad. Summary "active-ports" display was misleading.
Matches known ice/E810 LACP pathologies (Talos #12586 class).
DECISION: drop LACP; lab bonds → active-backup (host-side failover,
bond MAC on active port), switch → six plain tagged bridge ports, no
LAG. Keeps link redundancy, removes the LACP dependency entirely.
RouterOS 7.24 upgrade stands (wanted the bug-fix window regardless;
release notes fixes + current stable).

## 2026-08-21 23:55 — TRUE root cause: E810 Safe Mode + FEC mismatch
Correction to 22:30 entry: RouterOS was EXONERATED. Post-upgrade (7.24)
bonds aggregated cleanly but datapath stayed dead. Active-backup pivot
(no LACP) + plain tagged switch ports let host TX flow (all four host
MACs learned on VID 30) but host RX stayed dead. Chased through: IncusOS
internal-bridge architecture discovery (nft.go: _p/_i/_v/_b devices) →
added vlan_tags=[30] to fast parents (correct + kept, but insufficient).
tcpdump via macvlan taps in containers proved lab01→nas01 ARP arrives;
switch tx counters proved switch transmits toward labs; lab NIC rx_bytes
ZERO — frames die below the MAC, ports in promisc. FEC knobs on switch
(fec74/fec91/off, autoneg off): no effect, link never bounced (likely
unsupported at 10G on 98DX8216).
/os/1.0/debug/log delivered the verdict: ice "DDP package file was not
found... Entering Safe Mode" (IncusOS base image ships NO firmware
packages at all — checked mkosi.conf.d) and "Requested FEC: RS-FEC,
Negotiated FEC: NONE, Autoneg Negotiated: False" on the 25G DACs forced
to 10G. nas01 works because port 7 is a 10G optic (no FEC/autoneg
games) and Realtek. This one fault explains EVERYTHING back to the
first LACP flap (hosts never received a single switch LACPDU).
debug/:run-script requires S/MIME signing with the upstream image key —
no host-side ethtool confirmation possible.
Merged: networking#15 (drop LAGs, plain tagged ports 1–7),
fleet#4 (active-backup + vlan_tags + seeds). Switch/tofu converged;
manual diagnostic pokes reverted; test containers deleted.
Remediation paths (T48): (a) upstream lxc/incus-os issue — ship
intel ice DDP firmware; (b) 10G-rated DACs/optics for the six lab
links. Draft issue text ready; Josh to approve filing.

## 2026-08-22 00:20 — Upstream issue filed
Josh approved; filed lxc/incus-os#1305: ice Safe Mode from missing
intel/ice/ddp/ice.pkg, with the observed FEC line and the E810 RX
consequence. Requests DDP in the image (or a supported vendor-firmware
load path). Watch for upstream response; fix arrives as a routine
signed update (stable channel, 6h checks) once shipped.

## 2026-08-22 00:50 — Upstream PR branch prepared
Interim ruling: mgmt path (2.5G, incusbr0 NAT) serves VM traffic until
6x 10G SFP+ DACs arrive (~2 days); instances stay OFF VLAN 10 itself.
Forked lxc/incus-os → jmgilman/incus-os; branch
fix/ship-ice-ddp-firmware @ 8e9657d5: one-line add of
firmware-intel-misc to base packages (non-free-firmware component
already enabled upstream; their build.yml CI validates). Commit
"base: Ship Intel ice DDP firmware", DCO signed, Fixes #1305.
Josh opens the upstream PR himself.

## 2026-08-22 05:15 — WD Red Pros seated, zeroing overnight
Josh hot-plugged all four into nas01 (N5 Pro bays are hot-swap; all
detected immediately): WD6002FFWX 6TB x4, serials K1JXHD3D/K1JXPWVD/
K1JXR3BD/K1JXR5DD, SMART passed. :wipe-drive on TRIM-less HDDs falls
back to blkdiscard -z FULL-DEVICE ZERO (ClearBlock: secure discard →
discard → zero; subprocess ignores request ctx, so client timeouts are
harmless — verified via debug/processes: exactly one blkdiscard -z per
drive, running parallel). ~8h ETA. Lesson for the runbook: the wipe
endpoint zeroes entire HDDs; budget hours, or pre-wipe via rescue
stick when time matters.
fleet#5 open (nas01 hdd zfs-raidz1 pool in storage deploy, OS-level
only, 29 tests green). REMAINING SEQUENCE once zeroing completes:
1) moon run fleet-cluster:storage (creates hdd; escrow assert fails
   as designed), 2) escrow zfs_pool_hdd_recovery_key to
   fleet/nas01/incusos.sops.yaml (secrets PR), 3) POST :retrieved,
   4) rerun deploy (clean) + verify raidz1 ONLINE ~18TB, 5) merge
   fleet#5, resolve T19.
Also this turn: mgmt-path interim ruling journaled earlier; 10G DACs
arrive ~2 days (T48 retest then).

## 2026-08-22 — PR #1306 reworked per stgraber review
stgraber (CHANGES_REQUESTED): firmware ships via app-build/applications.json
(linux-firmware git pulls), not Debian packages. Reworked branch @ 90956d6e:
add intel/ice/ddp to linux-firmware-base install/clean targets, plus
build-applications.py materializes WHENCE "Link:" entries for installed
dirs (git tree has no real symlinks; ice driver requests unversioned
ice.pkg which exists only as a WHENCE link). Same latent bug affected
gpu-support image (i915/nvidia links never created). Link logic tested
locally against real 20260810 WHENCE: ice.pkg created+resolves, no
cross-image leakage. Commit retitled "app-build: Ship Intel ice DDP
firmware", DCO as Josh, force-pushed → PR auto-updated.

## 2026-08-22 08:55 — Wipe status: 3 done, drive 1 re-zeroing; reboot no-op
Drives 2–4 zeroing COMPLETE (~9h, matches estimate). Drive 1
(K1JXHD3D): the first client-timed-out wipe request survived
disconnect, queued on incus-osd's storage lock behind the duplicate,
and started a REDUNDANT second zero at 14:01 UTC (~7h remaining).
Lesson: duplicate wipe POSTs queue server-side; never re-POST a
wipe after a client timeout — check debug/processes first.
Attempted nas01 :reboot to kill it: NO-OP — node never rebooted
(kthreadd start Aug21), API blipped ~4 min then recovered; shutdown
presumably wedged behind the same storage lock. No second attempt:
nas01 has no AMT and no ATX wiring (physical-only recovery). Cluster
healthy throughout, nas01 still leader.
Started hub process hdd-wipe-watch: polls blkdiscard every 10 min;
on exit runs the storage deploy (creates hdd pool, halts at escrow
gate by design) and prints pool state. Escrow+ack+rerun+merge fleet#5
when a human is back.
