---
id: 015
title: Session opened, goal pending
started: 2026-08-24
---

## 2026-08-24 17:18 — Kickoff
Goal for the session: not yet stated. Josh asked for a new session; the actual
request follows.

Current state of the world:
- Journal root is the `journal/jmgilman` worktree at `.wt/journal-jmgilman`;
  sessions 011, 012, and 014 remain `in-progress` and are untouched by this
  session.
- Loaded required skills (`git`, `worktrunk`), `TECH_NOTES.md`, and the last
  three closed summaries (013, 010, 009).
- Lab state: four-node Incus cluster (nas01 + lab01–03) live with encrypted
  `data` pools and nas01's 17.4TB `hdd` raidz1; day-2 convergence flows only
  through `fleet/cluster/` pyinfra.
- Standing blocker T48: VLAN 30 lab datapath dead switch→host because IncusOS
  ships no ice DDP, so the E810s sit in Safe Mode passing broadcast/multicast
  only. FEC leg closed by the 10G DACs. Waiting on the stable IncusOS release
  carrying lxc/incus-os#1306 (merged 2026-08-22; newest published build is
  still `202608201218`, which the nodes run, and `auto_reboot: false`).
- Other open threads: `just plan` verification for `sw-core01` after
  `aws sso login`, `svc-tofu` RouterOS password rotation, T44 (Operations
  Center spike), T45 (PiKVM default creds), T46 (secrets checkout path),
  T47 (meshcommander disposition), T49 (upstream pyinfra-incus ops).

Plan: wait for Josh's actual request, then read `.journal/VISION.md` and any
task-relevant skills before substantive work.

## 2026-08-24 17:55 — Goal: generalized VM backup design (opens T16's backup half)
Josh's ask: brainstorm a generalized backup process for lab VMs. His priors —
disk-level backup is a poor fit because most guests will be bootc/ostree-style
with a large immutable layer; restic looks attractive but he wants alternatives
considered; wants a receiving "server" on nas01 tied to the 17.4TB `hdd` array;
Mac/Windows desktop backup is a nice-to-have, not a requirement.

Ran three parallel researcher slices (engines / Incus+ZFS native / guest+desktop
reality). Load-bearing findings, all upstream-cited:

- Engines (versions as of 2026-08-24): restic 0.19.1 + rest-server 0.14.0 is the
  best receiver fit — dumb storage-agnostic HTTP daemon, native `--append-only`
  + `--private-repos` + htpasswd + `/metrics`, client-side keys, one static
  binary for Linux/macOS/Windows. Kopia 0.23.1 is the runner-up: better desktop
  GUI and cross-client dedup, but repository-server mode can decrypt everything
  (kopia#4772) and its only real immutability story is S3 object lock. PBS 4.2.5
  is a genuine standalone appliance but wants ~4GiB + 1GiB/TiB RAM (~21GiB for
  this datastore) plus an SSD special vdev on HDDs, and has no macOS/Windows
  client. Borg 2.0.0b23 is still explicitly "do not use in production"; Borg 1.4
  is one-repo-per-client and Unix-only. rustic/backrest = adjuncts, not
  receivers. Restic append-only implies clients cannot prune: maintenance must
  run NAS-side with a separate credential (a feature, not a defect).
- Incus/ZFS: no Incus-native S3/off-site backup target exists; running VM
  snapshots are crash-consistent only (no QEMU guest-agent freeze/thaw wired
  into Incus snapshots); Incus warns it owns its ZFS subtree, so sanoid/zrepl
  must not manage those datasets — and IncusOS has no shell to run them anyway.
  Path to using `hdd`: IncusOS `create-volume` with `use: "incus"`, then
  `incus storage create --target nas01 backup zfs source=hdd/<vol>` plus
  placeholder pool definitions on lab01–03 to satisfy the all-members
  invariant. Documented upstream; host-path disk devices work but IncusOS
  publishes no stable mount path, so prefer the volume route.
- Guests/desktops: bootc splits cleanly — `/usr` image-owned, `/etc` 3-way
  merged, `/var` persistent; so back up declared `/etc` overrides + `/var/lib`
  subtrees + app-native dumps, and never blind-restore an old `/etc` onto a
  newer image. App-aware artifacts are mandatory for Vault (raft snapshot +
  original unseal material), Zitadel (Postgres dump; binary is stateless),
  Talos/etcd (`talosctl etcd snapshot`), SQLite (`VACUUM INTO`), Garage
  (`garage meta snapshot` + independent object copy). Mac bare-metal restore =
  reinstall + Migration Assistant from Time Machine (Samba SMB3 + `fruit`,
  dedicated quota'd share); Windows bare-metal = Veeam Agent Free image to SMB;
  restic/kopia are data-only on both. Dead-man-switch monitoring
  (Healthchecks-style) is the only reliable detector of a client that stopped
  existing; Prometheus metrics are secondary.

My synthesis, pending Josh's reaction: three planes by who owns the truth
(rebuildable → git/CI; state → restic to nas01; keys/identity → existing SOPS +
KMS + YubiKey root of trust, which must never depend on the backup system).
Incus scheduled snapshots stay a short-horizon rollback tier only. Off-site =
`restic copy` of a critical subset to S3 in the lab account, not a second NAS.
Next step proposed: a throwaway spike (rest-server container on nas01 + one
Linux guest + the Mac) to prove hdd wiring, append-only isolation, and a
restore drill from escrowed material alone, before any design doc.

Research transcripts: `history://BackupEngines`, `history://IncusZfsNative`,
`history://GuestsAndDesktops`.

## 2026-08-24 18:05 — Spike executed and torn down (Mac excluded per Josh)
Josh approved the spike, scoped to a test Linux VM only — no Mac client. Ran it
live on the cluster and destroyed everything afterward. Full procedure,
measurements, and findings: `.journal/015/SPIKE_BACKUP.md`.

All five objectives passed: `hdd` exposed to an instance (IncusOS
`create-volume use=incus` → two-phase cluster pool with per-member sources →
custom volume pinned to nas01, 15.73TiB visible, mounted at `/srv/repos`);
rest-server 0.14.0 over TLS 1.3 with `--private-repos --append-only`; a
Debian 13 VM on lab01 pushing bootc-shaped state (declared `/etc` overrides +
`/var/lib` subtrees + a `VACUUM INTO` SQLite dump, cache excluded) through a
manifest-driven runner; a restore on a clean container on lab02 with escrowed
material only; and NAS-local `forget --prune` + `check`.

Numbers: 131MiB first backup in 2.4s, 21MiB incremental after 20MB churn,
420MiB new in 4.4s (~95MiB/s), full restore 1.4s, prune reclaimed 573M→153M in
0.87s, receiver-side `rm -rf` of `snapshots/` recovered by volume-snapshot
restore in 0.16s with a clean `restic check`.

Restore fidelity was exact: content hash matched, and mode 0600, symlink
target, POSIX ACL, and user xattr all survived; the hooked SQLite dump passed
`integrity_check` with the right row count.

Four findings that change the design:
- `rest-server --prometheus` (0.14.0) exports ONLY Go/process families — no
  repo size, no request counters, no last-write time, even after traffic. The
  receiver cannot report backup freshness; per-client dead-man checks plus a
  NAS-side snapshot-age/size job are mandatory, not optional.
- `/metrics` returns 401 to a normal client credential under `--private-repos`;
  it needs `--prometheus-no-auth` and network-layer restriction instead.
- Append-only permits lock deletion: a client CAN `unlock --remove-all`. Fine
  for stale locks after a killed backup, but it is an interference vector
  against concurrent maintenance. Snapshot/pack deletion is genuinely blocked
  (403), repo-root DELETE is 405.
- `incus storage delete backup` destroyed the underlying `hdd/backup` dataset,
  so the IncusOS `delete-volume` calls then failed with "dataset does not
  exist". Once handed to Incus the dataset is Incus-owned: pool deletion is
  destructive to the whole backup corpus, which the pyinfra convergence must
  treat as a guarded operation.

Teardown verified: `guest01`, `restore01`, `backupd` deleted; `repos` volume +
`spike0` snapshot + cluster pool `backup` deleted; all four nodes back to their
original IncusOS volume sets (`data:[incus]`, `local:[incus]`, `hdd:[]`); local
credential files shredded. Only Incus's own cached VM image volume remains
(self-expiring). No repository state, no lab config drift.

Next: Josh's open decisions from the brainstorm are still open (single-target
acceptance, RPO/retention, desktop scope). With the spike green, the real work
is the `fleet/cluster/` pool + receiver definition, per-guest manifests, the
SOPS credential layout, and a docs design/ADR — plus a decision on the lab CA
cert for the receiver.

## 2026-08-24 18:25 — Is the wiring expressible in fleet/cluster today? Yes, for storage
Checked the current `fleet/cluster` project (now at `b2b13cd`, "drive every Incus
call through pyinfra-incus 0.2.4") against the spike's procedure.

Storage plane needs NO new ops. `incus_os_storage_volume` creates `hdd/backup`
(and the lab placeholders); `cluster_storage_pool(per_member_config=...)` takes
heterogeneous member sources because `source` is in
`MEMBER_SPECIFIC_POOL_CONFIG_KEYS` and `validate_storage_pool_member_config`
compares only declared keys; `storage_volume(target="nas01", config=...)`
creates the pinned `repos` volume and can carry `snapshots.schedule`/`expiry`;
`instance(target=..., devices=...)` expresses the receiver with both the disk
device and the proxy device, and `instance_state` starts it. Verified by a
read-only probe deploy (`--debug-operations`) against the real inventory: all
seven operations construct and order correctly.

Notable: `cluster_storage_pool` itself REQUIRES `per_member_config` keys to
equal the cluster member set, so the lab placeholder volumes are enforced by
the op, not merely by Incus.

Real gap is guest-side: pyinfra 3.10 ships connectors chroot/docker/dockerssh/
local/ssh/terraform/vagrant/fake — no incus/lxd connector — and the project
inventory is `@local` driving the `nas01` remote. So rest-server's in-container
config cannot be converged from this project. Options: (a) purpose-built pinned
image built in git+CI (matches the decided image-distribution plan), (b)
cloud-init `user.user-data` via `instance(config=...)`, (c) add an `incus exec`
connector/op to pyinfra-incus (T49-style upstream promotion). Prefer (a) with
(b) only for per-instance secrets.

Also to encode when implementing: `incus_os_storage_volume` rejects quota/`use`
drift (IncusOS has no volume update endpoint), so a corpus quota must be set at
creation; and pool deletion destroys the dataset (spike finding), so
`present=False` on this pool is data-destroying and needs a guard. The
`HDD_POOL` comment in `config.py` ("OS-level only ... waits for T16") is the
line this work flips.
