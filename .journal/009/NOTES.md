---
id: 009
title: Session opened, goal pending
started: 2026-08-20
---

## 2026-08-20 20:03 — Kickoff
Goal for the session: not yet stated. The user asked only to create a new
session; the actual request will follow and will be appended here.
Current state of the world:
- Journal root is the `journal/jmgilman` worktree at `.wt/journal-jmgilman`
  (clean, in sync with origin). Sessions 001-008 are all closed.
- Loaded startup context: `SKILLS.md` (`git`, `worktrunk` — both loaded),
  `TECH_NOTES.md`, and summaries for 006, 007, 008.
- Lab state per 008: `gw01` (VyOS) owns L3/DHCP/DNS/firewall/NAT/Tailscale
  routing; `sw-core01` is OpenTofu-managed with an empty plan; `sw-mgmt01` is
  hand-managed at `10.10.70.2` with an escrowed backup; `nas01` runs IncusOS as
  the first Incus cluster member with both SN7100 drives still blank pending a
  storage design; `sandbox01` is converged via `GilmanLab/sandbox` pyinfra.
- Open threads carried in from 008: rotate `sw-core01` `admin` and `svc-tofu`
  passwords, rule on the leftover v1 CA certs, upstream the
  `routeros_ip_service` import defect, migrate the pinned self-signed CA when a
  device PKI intermediate exists, test the TEG-3102WS `cfg_upload` restore path,
  and re-add the gw01 `eth3` escape hatch if factory switch access is needed.
- `.journal/VISION.md` holds the running T-item tracker; consult it once the
  goal is known.
Plan: wait for the user's actual request, then scope work against
`.journal/VISION.md` and create implementation worktrees in the appropriate
repository per the sub-repository workflow.

## 2026-08-21 11:49 — Goal set: bring lab01–03 online
Josh chose bootstrap step 2 for this session: configure the OOB links on the
lab nodes and install IncusOS on `lab01`–`lab03`, joining them to the `nas01`
cluster (VISION step 2; touches T01/T03/T06/T12). NAS storage (T19 + NAS-OS
design) deliberately deferred to a later session; clarified that the Synology
drives are already backed up to a large external HDD, so only
install/wipe remains.
Operations Center ruling: do NOT set up OC before the node joins. Evidence:
IncusOS provider is runtime-modifiable (`SystemProviderConfig` documented as
the modifiable part, `Registered` state flag), so post-install registration
with a future OC needs no reinstall; OC's documented flow only provisions
clusters from freshly seeded self-registered servers (adopting an existing
cluster is undocumented, and nas01 pre-exists OC under any ordering); OC wants
to own seeding/updates, colliding with decided fleet + incusos-builder model
(T25/T26/T30); OC is young (announced 2025-12-21, v0.81). Plan: OC becomes a
follow-up spike on `sandbox01` or a cluster VM — verify late registration +
existing-cluster visibility empirically. Add a tracker item at close.
Next: inventory the lab-node hardware facts (AMT state, NIC MACs, cabling)
and drive the proven seeded-install procedure per `rebuild-nas01.md`,
adapted for lab01–03.

## 2026-08-21 11:58 — Recon complete: nodes off, AMT unprovisioned, join path settled
Facts established (all live-verified or primary-source):
- Cabling: every lab-node link is installed (PHY-006..017). No new cables.
- sw-mgmt01 port state via JSON API: gw01 trunk + nas01 at 2.5G; lab AMT
  ports 3/5/7 and lab02/03 mgmt ports 4/6 show 100M_F standby links; lab01
  mgmt port 2 no link. Reading: all three MS-02s plugged in but powered OFF
  (100M = PHY standby). ATX unwired + AMT dead → power-on is physical.
- AMT at 10.10.70.11-13: no ping, 16992 closed, no DHCP leases on gw01 →
  AMT unprovisioned (v1-era gw01 reservations + MACs exist but were never
  live on VLAN 70). MEBx session per node required.
- AMT virtual media: my stale belief that AMT 16 removed storage redirection
  is WRONG — USB-R replaced IDE-R in AMT 11 and persists. So AMT-mounted ISO
  installs are plausible on MS-02 Ultra (vPro), but unproven → keep USB as
  the install path, test USB-R as T01 follow-up.
- Join mechanics: incus-os seed has NO cluster type; joining = Incus preseed
  `cluster` section (token) or post-boot `PUT /1.0/cluster` via API. Chose
  post-boot API join: no token baked into images, mirrors the proven nas01
  post-boot flow. Cluster pool `local` (zfs) member source is `local/incus`
  (OS-created dataset) — expected member_config at join.
- MS-02 Ultra disks: Patriot P300 128GB (OS) + 990 EVO Plus 2TB (data) →
  nas01's install.target (NVME, max_size 200GiB) carries over verbatim.
- Tooling: incus remote to nas01 healthy (database-leader ONLINE);
  incusos-builder source at ~/code/componere/incusos-builder is exactly the
  fleet pin 065b9e83.
- Missing facts: the three 10GbE mgmt NIC MACs (harvest at power-on via DHCP
  leases from old OS, else BIOS via console); AMT provisioning.
- Stale lease noticed: 10.10.10.232 "ubuntu-server" bound to nas01's 10GbE
  MAC (38:05:25:37:8d:7b), from install day. Harmless; expires 22:26 UTC.
Decision: lab mgmt addresses go static-in-seed like nas01 (not DHCP
reservations); address-plan sentence claiming seed-DHCP needs amending at
wrap. AMT stays DHCP with the existing reservations (no added failure
coupling — gw01 owns VLAN 70 L3 anyway).
Next: author fleet configs (MAC placeholders), generate + escrow AMT MEBx
passwords, then the rack walk: power on ×3, harvest MACs, MEBx (possibly
PiKVM-driven via TESmart hotkey channel switch — untested, T01), USB installs.

## 2026-08-21 12:07 — Prep done; blocked on rack walk
Completed without hands:
- Fleet: branch `feat/lab-node-configs` pushed with `nodes/lab0{1,2,3}/`
  configs — nas01 pattern, static .11/.12/.13, apply_defaults:false,
  bootstrap-admin cert seeded, install.target unchanged (P300 128GB OS drive),
  release pinned `202608201218` = nas01's RUNNING release (verified live via
  `incus query nas01:/os/1.0` — no update drift, latest stable). MAC fields
  are placeholders (00:..:00); PR waits for harvest. All three configs pass
  the pinned builder's validate.
- Secrets: #29 MERGED — `fleet/lab0N/amt.sops.yaml` (username/password),
  generated locally, never printed, metadata check green. SSO needed a fresh
  `aws sso login` (Josh approved in browser).
- PiKVM: API alive, default admin/admin credentials WORK — rotate + escrow
  later (flag). Snapshot + HID key events verified against nas01's console.
- T01 negative result: TESmart channel switching via PiKVM HID hotkeys
  (double ScrollLock + digit) does NOT work — video source stayed online
  across attempts. Explanation: PiKVM USB sits on a TESmart pass-through hub
  port (host keystrokes work — proven in 008 — but the switch never parses
  them). Fix options: move PiKVM USB to the console keyboard port, or wire
  RS232 (documented control path). Front-panel switching for now.
- nas01 console shows "Some encryption recovery keys have not been retrieved
  yet!" — reconcile against the 008 escrow during verification.
- kvm01 input-to-machine mapping is undocumented (T02) — map it during the
  walk.
Rack-walk checklist for Josh: (1) power all three MS-02s; (2) note/fix which
TESmart port PiKVM USB uses; (3) front-panel-switch channels on request so I
can read BIOS/MEBx screens; MEBx typing (passwords included) can be injected
by me via HID once the channel shows the right node. MAC harvest: watch gw01
leases for old-OS DHCP first, BIOS screens as fallback. Then: build 3 images,
USB dd per node, install, post-boot API join, escrow keys per node.

## 2026-08-21 12:10 — nas01 recovery-key warning reconciled
The console warning was only the unacknowledged-retrieval flag
(`state.encryption_recovery_keys_retrieved: false`). Verified BOTH live keys
against `fleet/nas01/incusos.sops.yaml` by sha256 (LUKS `encryption_recovery_key`
and `zfs_pool_local_recovery_key`): MATCH. Acknowledged via the dedicated
`POST /os/1.0/system/security/:retrieved` endpoint (a plain PUT of the state
field is silently ignored); flag now true. TUI banner redraws lazily — check
it clears by next boot.
Exposure note: my redaction slip printed nas01's ZFS pool recovery key into
the session transcript (LUKS key stayed redacted). Same exposure class 008
accepted for svc-tofu; rotate at will — requires IncusOS pool-key rotation
support (not investigated).
Lease poll 12:10: lab nodes still dark — waiting on the rack walk.

## 2026-08-21 12:41 — Decision reversed: AMT goes static-in-MEBx
Josh proposed static AMT addresses instead of DHCP reservations; he is right
and this supersedes my 11:58 ruling. Rationale: (1) with static, a laptop on a
VLAN 70 access port reaches AMT even during a gw01 outage — exactly when OOB
matters; DHCP would lapse at lease expiry mid-outage. (2) The v1-era
reservation MACs were never observed live (zero lease attempts) — a wrong MAC
would strand AMT in the dynamic pool. (3) Consistent with 008's static ruling
for switches. MEBx values per node: 10.10.70.11/12/13, mask 255.255.255.0,
gw 10.10.70.1.
Clarified: this does NOT remove the mgmt-NIC MAC harvest — the seeds bind the
10GbE NICs by strict_hwaddr (different NICs; AMT MACs were already known).
Executed the clean cutover: networking#13 removed the three dead lab0N-amt
static-mappings from gw01's template (full network:check green), squash-merged,
deployed via the guarded vyos-sync (pending_save false before and after), and
live-verified zero lab0N-amt mappings remain. Address-plan doc amendment
(AMT rows: reservation → static interface address) queued for the wrap docs PR.

## 2026-08-21 12:49 — AMT gateway live on nas01 (step 3 done early)
Josh's refined sequence accepted: (1) he sets AMT static + reboots per node,
(2) I verify reachability, (3) AMT tooling, (4) live-Ubuntu boot to harvest
NIC/drive facts, (5) build seed ISOs, (6) attempt install over AMT USB-R.
Step 3 executed ahead of step 1:
- Firewall verified first: MGMT_FORWARD has blanket "Allow management to
  OOB" — a VLAN 10 gateway reaches AMT with no policy change. (Sandbox was
  never an option: VLAN 40 → OOB is design-blocked.)
- Deployed `meshcommander` Incus container on nas01 (images:debian/13,
  node 20, meshcommander@0.9.5-a npm, systemd unit, restart=always) with an
  Incus proxy device 0.0.0.0:3000 → container 127.0.0.1:3000. UI verified
  end-to-end from the laptop browser at http://10.10.10.14:3000/ ("No known
  computers" landing page, screenshot taken). MeshCommander covers KVM, SOL,
  power, and USB-R storage redirection — everything steps 2-6 need.
- Known risks flagged: MeshCommander is archived upstream (MeshCentral is
  the maintained fallback); the UI is unauthenticated HTTP on VLAN 10 — do
  NOT save AMT passwords into its computer list; enter per session. Decide
  keep-vs-teardown at wrap. This is also the first real workload on nas01 —
  commissioning tooling, placement revisit noted.
- MEBx checklist addition for Josh: beyond password + static IP
  (10.10.70.11/12/13, /24, gw 10.10.70.1), enable SOL + storage redirection
  + KVM, and set User Consent/opt-in to NONE (headless KVM fails otherwise).

## 2026-08-21 15:30 — lab01 AMT verified; IDER boot ruled out; USB install handoff
Step 1-2 results (lab01): Josh set MEBx static 10.10.70.11 (all three AMT
passwords are HIS values now — secrets#30 synced them; my generated ones are
dead). Gotchas hit: BIOS-integrated MEBx commits on Save & Exit only; AMT 19
is TLS-only (16993/16995 open, 16992/16994 dark by design — my laptop probes
were ALSO firewalled: home→OOB passes ICMP but not AMT ports; MGMT→OOB is the
blanket-allowed path, so the nas01 gateway placement is REQUIRED, not just
convenient). Digest auth verified with curl (200). MeshCommander connect
needed Digest/TLS mode — its combobox ignores tab.select; set el.value +
dispatch change event. AMT state: ME 19.0.5 ACM, redirection+SOL+KVM active,
consent Not Required. KVM verified live (AMI setup tiles rendered, keyboard
injection worked — drove the UEFI shell).
MAC harvest: UEFI shell has NO network drivers (ifconfig -l empty after
connect -r). Winning method: boot the resident old OS (Fedora 43 WS) and
watch gw01 leases — lab01 mgmt 10GbE = 38:05:25:35:48:87 (= AMT MAC + 1;
pattern to verify per node). Fedora also DHCPed the shared 2.5G NIC on
VLAN 70 — validates leaving it unconfigured in seeds.
Step 6 verdict: AMT IDER/USB-R BOOT IS NON-VIABLE on MS-02 Ultra (AMI
2.22.0059, ME 19.0.5). Two reproduced firmware wedges: Reset-to-IDER-CDROM →
black screen, no CD reads, no boot events, input dead (physical AND remote
per Josh at the local monitor); once wedged only a cold AMT power cycle
recovers. Also learned: MeshCommander IDER streams from the BROWSER TAB
(reload = session killed), and each reset costs a "Waiting Up to 8 Minutes
For KVM FW" delay before video returns. AMT keeps KVM/SOL/power/console
duties; install media = USB (fleet configs reverted to raw, force_reboot
false; force_install true stays for the dirty disks).
lab01.img (raw, 202608201218, sha256 bb8edd09…) built and handed to Josh for
dd + boot. While it installs: MEBx on lab02/03, then remote power-on + lease
harvest per node, image builds, same stick re-dd'd.

## 2026-08-21 16:13 — lab01 JOINED: 2-node cluster, smoke passed
Secure Boot detour (new fleet knowledge): IncusOS needs its own SB keys.
AMI "Factory Key Provision" re-installs factory keys on every reset while in
Setup Mode — it MUST be disabled BEFORE Reset to Setup Mode, else the clear
silently undoes itself and the USB keeps failing SB validation. Working
recipe: Secure Boot Mode Custom → Factory Key Provision Disabled → Reset to
Setup Mode → Save & Exit → boot USB → installer auto-enrolls IncusOS
PK/KEK/db (User Mode after; signed db/dbx updates flow automatically). The
console then showed "Applying Secure Boot certificate update" on first boot.
lab01 first boot: static mgmt(10.10.10.11) ✓, fingerprint console-vs-API
match (3f0856d0…e82fe66) ✓, remote added, recovery keys escrowed
(secrets#31 MERGED) + retrieval acked BEFORE join. Join: token from
`incus cluster add nas01:lab01`, PUT /1.0/cluster on lab01 — payload needs
server_name (error message told us), cluster cert from
~/.config/incus/servercerts/nas01.crt, member_config storage-pool
local/source=local/incus (as predicted). Joined in ~15s:
lab01 ONLINE database-standby. Smoke: alpine container --target lab01,
ping 10.10.10.1 0% loss, deleted. Removed the stale standalone lab01 remote
(join adopts the cluster cert).
Remaining: lab02/03 MEBx (Josh) → AMT verify → remote power-on → Fedora
lease harvest → config MACs → build raw images → USB per node (with the
SB recipe) → escrow+join each. PiKVM note: Josh re-seated the lab01 KVM
input; earlier stale-frame confusion explained by the disconnected cable.
