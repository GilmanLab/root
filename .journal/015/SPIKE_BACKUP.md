# Spike: restic + rest-server backup receiver on nas01

Executed 2026-08-24 (session 015). Deliberately throwaway: everything created
here was destroyed at the end. This document is the surviving artifact — the
procedure that worked, the numbers, and the findings that must shape the real
implementation in `fleet/cluster/`.

Versions used: Incus client 7.3, IncusOS `202608201218` (Incus 7.0.0 / QEMU
11.1.0), rest-server 0.14.0, restic 0.19.1, Debian 13 guests.

## What the spike had to prove

1. The 17.4TB `hdd` pool can be exposed to an Incus instance on nas01.
2. rest-server can receive backups over TLS with per-client isolation and
   append-only enforcement.
3. A guest can push declared state (bootc-shaped) with app-native dumps.
4. A clean host can restore with escrowed material only.
5. NAS-side `forget`/`prune`/`check` works and costs something measurable.

All five passed. Two negative findings matter more than the passes (see below).

## Storage wiring (worked, verbatim)

```bash
# 1. IncusOS volume on the encrypted hdd pool, marked for Incus consumption
incus admin os system storage create-volume nas01: --target nas01 \
  -d '{"pool":"hdd","name":"backup","use":"incus"}'

# 2. Placeholder volumes on the labs, because a cluster pool must exist on
#    every member (nas01-only pools are unsupported)
for n in lab01 lab02 lab03; do
  incus admin os system storage create-volume nas01: --target $n \
    -d '{"pool":"data","name":"backup","use":"incus"}'
done

# 3. Two-phase cluster pool creation: per-member sources, then finalize
incus storage create nas01:backup zfs --target nas01 source=hdd/backup
for n in lab01 lab02 lab03; do
  incus storage create nas01:backup zfs --target $n source=data/backup
done
incus storage create nas01:backup zfs

# 4. Repo volume, pinned to nas01
incus storage volume create nas01:backup repos --target nas01
incus storage volume attach nas01:backup repos backupd repos /srv/repos
```

Result inside the container: `hdd/backup/custom/default_repos` mounted at
`/srv/repos`, `df` reporting 16T; `incus storage info` reported 15.73TiB total.

Receiver exposure reused the `meshcommander` pattern: a `proxy` device
(`listen=tcp:0.0.0.0:8000` → `connect=tcp:127.0.0.1:8000`), so the endpoint is
`https://10.10.10.14:8000/` on VLAN 10. A client VM on lab01 reached it through
lab01's `incusbr0` NAT with no extra routing.

## Receiver configuration that worked

rest-server flags: `--path /srv/repos --listen 127.0.0.1:8000
--htpasswd-file ... --private-repos --append-only --prometheus
--prometheus-no-auth --tls --tls-cert --tls-key --tls-min-ver 1.3 --log -`,
under a systemd unit with `ProtectSystem=strict`, empty capability set, and
`ReadWritePaths=/srv/repos`.

Credential split proven in practice, and it is the important part:

- HTTP upload credential (htpasswd, bcrypt) — on the client, per client.
- Repository encryption password — on the client, escrowed separately; restic
  reads it from `RESTIC_PASSWORD_FILE`.
- NAS-side maintenance uses the local path `/srv/repos/<client>` plus the same
  repository password; it never touches the HTTP layer, so maintenance needs no
  append-only exemption.
- `RESTIC_REST_USERNAME` / `RESTIC_REST_PASSWORD` work, so credentials stay out
  of the repository URL and out of `ps`.

## Measurements (single client, VLAN 10, raidz1 HDD target)

| Operation | Result |
|---|---|
| `restic init` over TLS | 3.2s |
| First backup, 130.9MiB / 406 files | 2.4s (~55MiB/s) |
| Incremental after 20MB churn | 21.1MiB added, 1.4s |
| Bulk backup, 570MiB processed / 420MiB new | 4.4s (~95MiB/s) |
| Full restore, 150.6MiB / 416 entries, clean host | 1.4s |
| NAS-local `forget --prune` (dropping 420MiB snapshot) | 0.87s, reclaimed 573M → 153M |
| NAS-local `restic check` | 0.77s |
| Custom-volume snapshot restore after receiver-side `rm -rf` | 0.16s |

Compression on this corpus: 1.02x (mostly incompressible test blobs) — not a
useful signal for real workloads.

## Proofs

- **Append-only holds where it matters.** Client `forget --prune` fails with
  `Remove(<snapshot/…>) failed: unexpected HTTP response (403)`; both snapshots
  survived. A direct `DELETE` of a pack returns 403, and `DELETE` of the repo
  root returns 405.
- **Cross-repo access denied.** guest01's credential against
  `/guest02/` returns 401 under `--private-repos`.
- **Read paths unaffected.** `cat config`, `snapshots`, `check`, and full
  `restore` all work with the client credential.
- **Restore fidelity from a clean host** (fresh container on lab02, given only
  repo URL, upload credential, repository password, CA cert): content hash
  identical to source (`bf89a0b0…`), plus mode 0600 preserved, symlink target
  preserved, POSIX ACL (`user:daemon:r--`) preserved, user xattr
  (`user.lab.test="proof"`) preserved, excluded `cache/` absent, and the
  hook-produced SQLite dump restored with `PRAGMA integrity_check` = ok and the
  expected 25000 rows.
- **ZFS backstop works.** After `rm -rf /srv/repos/guest01/snapshots` on the
  receiver, `incus storage volume snapshot restore backup repos spike0`
  recovered the repository in 0.16s and `restic check` reported no errors.

## Negative findings (these change the design)

1. **`rest-server --prometheus` exports nothing useful.** On 0.14.0 the
   `/metrics` endpoint serves only Go runtime and `process_*`/`promhttp_*`
   families — no per-repo size, no request counters, no last-write timestamp,
   even after generating traffic. Backup freshness therefore cannot come from
   the receiver: a dead-man switch per client is mandatory, plus a NAS-side job
   that reports snapshot age and repository size per client.
2. **`/metrics` needs `--prometheus-no-auth` when `--private-repos` is on.** A
   normal client credential gets 401 on `/metrics`; only the no-auth flag
   yields 200. So the metrics endpoint must be restricted at the network layer
   instead, not by HTTP auth.
3. **Append-only does not protect locks.** `restic unlock --remove-all`
   succeeded from the client against an append-only server (rest-server permits
   lock deletion by design). Good for stale-lock recovery after a killed
   backup; it also means a hostile client can interfere with concurrent
   maintenance. Not a data-loss path.
4. **Deleting the Incus pool destroys the IncusOS volume's dataset.**
   `incus storage delete backup` left `hdd/backup` gone, so the subsequent
   `delete-volume` calls failed with `dataset does not exist`. Once handed to
   Incus, the dataset is Incus-owned — the real automation must treat pool
   deletion as destructive to the backup corpus, and the pyinfra convergence
   must never recreate/delete this pool casually.
5. **`restic forget` needs an explicit policy or snapshot ID.** `forget --tag X
   --prune` with no policy aborts with `no policy was specified`. The
   maintenance job must always pass `--keep-*`.

## Carry-forward for the real implementation

- Wiring belongs in `fleet/cluster/` (pyinfra) as the `backup` pool +
  per-member volumes; the placeholder volumes on lab01–03 are part of the
  desired state, not an accident.
- Receiver should be a proper instance definition (image pinned, systemd unit
  baked) rather than an ad-hoc container with hand-installed binaries; verify
  the rest-server `SHA256SUMS.asc` signature, not just the checksum.
- TLS should use a real cert from the lab CA rather than the self-signed cert
  used here, so clients trust it without shipping a per-service CA file.
- Per-client identity: one htpasswd entry, one repository under
  `/srv/repos/<client>`, one repository password in SOPS, one dead-man check.
- Maintenance: a NAS-side timer running `forget --keep-…  --prune` and `check`
  per repository against the local path, plus a periodic `check --read-data
  --read-data-subset` sampling.
- Backstop: scheduled `snapshots.schedule` on the `repos` custom volume, with
  expiry, so a receiver-side compromise is recoverable.
- Off-site: `restic copy` of the critical subset to S3 in the lab account,
  driven from the receiver (needs an IAM role and a bucket, neither created).
