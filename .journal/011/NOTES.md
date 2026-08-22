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

## 2026-08-21 23:40 — DNS + certificate steps researched, cert candidate staged
Question: what does it take to get DNS and certs working for the four nodes.
Two more researchers (`history://ClusterCertOps`, `history://BrowserAuthFlow`).

Mechanics that matter:
- In a cluster, `cluster.crt`/`cluster.key` is what gets presented on
  `core.https_address`; `server.crt` is only the member's *client* identity.
  `incus cluster update-certificate <remote>: <crt> <key>` → `PUT
  /1.0/cluster/certificate`, may target any member (not leader-only), fans out to
  all members, live-swaps API/cluster/metrics/bucket/vsock listeners with **no
  daemon restart**. A *new private key* requires every member online.
- Trust store (client certs) and cluster membership are untouched, so
  `bootstrap-admin` keeps working. The CLI rewrites the targeted remote's pinned
  cert automatically.
- **No rollback**: the current cert's key exists only on the nodes. Failure mode
  is the IncusOS lost-certificate console procedure (recovery key, Secure Boot
  off, `patch.global.sql`). Preflight verified: all four ONLINE, fallback
  listener trusts `bootstrap-admin` (`active: false`).
- Browser credential: the UI generates its own (RSA-2048, 1000-day, PKCS#12 with
  3DES for macOS Keychain) and enrolls with a single-use trust token from
  `incus config trust add nas01: incus-ui`. No PKCS#12 export of the admin key.
  Positional name in 7.3; `core.remote_token_expiry` defaults to no time expiry.
- ACME is real in 7.3 (lego shipped whole, DNS-01, Route53/Cloudflare available,
  lab already delegates `acme.glab.lol`) but rejected for now: public CAs can't
  sign private-IP SANs, CT-log exposure, cloud creds in replicated cluster
  config. Lab-CA issuance is the eventual answer; no pipeline exists yet.

Staged (not pushed): `/tmp/monspike/incus-cluster.{cnf,crt,key}` — P-384,
10 years, `CN=incus.glab.lol`, SANs `incus/nas01/lab01/lab02/lab03.glab.lol` +
`10.10.10.11-.14` + loopback, fingerprint `27:86:A3:A9:…:E0:10`.

DNS: records must go in the Route53 **private** zone via `GilmanLab/aws`
(`aws/lab-foundation` owns the zone; `aws/keycloak` is the precedent for a root
authoring its own A record). gw01 re-fetches the zone every 1 min (VyOS
task-scheduler `dns-mirror-fetch-glab-lol`) and CoreDNS reloads every 30 s →
≤90 s propagation. Blocked on `aws sso login --profile lab-admin` (token expired).

Runbook written into the plan doc as Track 0 Phases 1-3. Nothing executed against
the cluster or AWS.

## 2026-08-22 00:05 — GitOps path for the cluster certificate
Josh: skip Phase 3 (auth) for now; and the hand-run `incus cluster
update-certificate` violates the GitOps/reproducibility motto — can it be
avoided?

Checked and ruled out two mechanisms:
- **Seed cannot carry it.** The IncusOS `incus` seed is only
  `incusapi.InitPreseed` (`incus-osd/api/seed/incus.go`); the app reads its cert
  from its own data dir (`app_incus.go:203` `GetServerCertificate` → `cluster`
  then `server`). So a rebuilt node cannot boot already presenting the cert.
- **No tofu resource.** `terraform-provider-incus` has `incus_certificate`
  (trust store, `client`/`metrics`) and `incus_server` (config keys only).
  Neither writes `cluster.crt`.

So the answer is the lab's existing bare-metal GitOps shape: declare in git,
converge with the re-runnable idempotent tool that already owns cluster day-2
state — `fleet/cluster/` (`fleet_cluster`). Planned shape: `IncusServerCertificate`
fact (`environment.certificate_fingerprint`, live `ea493033…9a0f`),
`cluster_certificate` operation (fingerprint diff → no-op or one
`incus cluster update-certificate`, refusing unless all members ONLINE),
`deploys/certificate.py`, SAN list in `config.py`, plus tests.

Two sources, same convergence code: (A) self-signed 10-year cert escrowed at
`fleet/cluster/tls.sops.yaml` — no external dependency, keeps IP SANs, rotation
is a file swap + converge; (B) ACME DNS-01 via `acme.*` config — Incus renews
itself daily, nothing escrowed, but no private-IP SANs (everything moves to
names), five hostnames into CT logs, a static Route53 credential inside
replicated cluster config, and a manual `_acme-challenge.<host>` CNAME per name
at Cloudflare (no Cloudflare provider in the stack; `aws/keycloak` did this by
hand once). Recommended A now, B later; lab-CA issuance is the eventual target
and lands in the same place.

Awaiting Josh's pick between A and B before writing the `fleet_cluster` code.
Phase 1 (Route53 records via `GilmanLab/aws`) is unchanged and still blocked on
`aws sso login --profile lab-admin`.

## 2026-08-22 09:55 — Option A implemented: fleet#6
Josh picked A (self-signed, escrowed, converged by `fleet_cluster`). Built it in
`GilmanLab/fleet` worktree `feat/cluster-certificate` → PR
https://github.com/GilmanLab/fleet/pull/6.

Shape as designed, with one improvement found while writing it: the certificate
is **public**, so it is committed at `cluster/tls/incus-cluster.crt` and the
converge diffs it with no secret access at all. Only the private key is escrowed.

- `config.py`: `TLS_CERT_FILE`, `TLS_KEY_SOPS_PATH`/`_FIELD`, `TLS_SUBJECT_CN`,
  `TLS_DNS_NAMES` (incus/nas01/lab01-03.glab.lol), `TLS_IP_ADDRESSES`
  (10.10.10.11-.14 + loopback), plus `tls_cert_path()`, `secrets_dir()`
  (`GLAB_SECRETS_DIR`), `tls_key_sops_path()`.
- `facts.py`: `IncusServer` → `GET /1.0`.
- `operations.py`: `certificate_fingerprint` (PEM → DER → sha256; verified it
  reproduces Incus's `environment.certificate_fingerprint` exactly — live
  `ea4930…9a0f` recomputed from the cached server cert),
  `server_certificate_fingerprint`, `offline_members`,
  `certificate_push_command` (`set -eu; umask 077; mktemp; trap rm; sops -d
  --extract '["key"]' > $key; incus cluster update-certificate`),
  `plan_cluster_certificate`, `@operation cluster_certificate`.
- `deploys/certificate.py`, `cli.py` `certificate` subcommand, runner
  `run_certificate`, moon task `fleet-cluster:certificate` (`runInCI: false`).
- `cluster/tls/{incus-cluster.crt,incus-cluster.cnf,README.md}` — cert, the exact
  openssl recipe, rotation + one-way-risk docs.
- 13 new tests (42 total pass): fingerprint math and rejections, committed cert
  covers every declared name/IP (DER byte search — no new dependency), cnf/config
  drift guard, no-op vs single push, offline-member refusal, empty-member
  refusal, path quoting. ruff + mypy clean.

Verified both branches by `pyinfra --dry` against the live cluster, zero
mutation: committed cert → 1 change planned; live cert copied in → 0 changes.
CI: "Cluster checks" pass.

Not converged. Blocked on (a) escrowing the key at
`GilmanLab/secrets fleet/cluster/tls.sops.yaml` and (b) `aws sso login` for both
that and the Phase 1 Route53 records. Converge with AMT/PiKVM available.

## 2026-08-22 10:30 — Upstream reuse audit (Josh: was this already in pyinfra-incus?)
Fair challenge; I should have checked `~/code/meigma/pyinfra-incus` before
writing code. Audit of 0.2.0 (the pinned dependency):

Already there, and I duplicated it:
- `facts.Server` — `incus query /1.0` (optional `?target=`), normalized +
  redacted. My `IncusServer` fact is the same read.
- `_control_plane.certificate_fingerprint` — `ssl.PEM_cert_to_DER_cert` +
  sha256, and it rejects private-key material. My version hand-rolled PEM regex
  + base64. **Fixed**: refactored to the stdlib technique with the same
  private-key guard (fleet#6 commit b347605), keeping only a DER-SEQUENCE sanity
  check because `PEM_cert_to_DER_cert` decodes base64 leniently.
- `facts.{ClusterMembers,StoragePools,TrustedCertificates,Warnings,...}` and
  `operations.{server_config,trusted_certificate,storage_pool,network,...}` —
  fleet_cluster already duplicates several of these for the same reason below.

Genuinely absent upstream:
- Any support for `incus cluster update-certificate` / `cluster.crt`.
  `operations.trusted_certificate` is the *trust store* (client/metrics certs),
  a different object entirely.

The structural reason fleet can't just call upstream: upstream's execution model
runs `incus` **on the target host** through that host's connector against the
local unix socket with sudo (`incus_command` builds bare `incus …`, no remote).
IncusOS has no SSH and no shell, so fleet_cluster runs on the operator machine
and prefixes every command with `nas01:` via its own `_cli.py`.

New finding worth promoting: **`INCUS_REMOTE=nas01 incus query /1.0` works**
(verified live, also with `?target=lab01` and `incus cluster list`). So a
`remote=` argument or env-based default upstream would make the whole upstream
library usable from the operator box, after which fleet_cluster could delete
`_cli.py` and its duplicated facts. Recorded in T49 along with the two
certificate gaps (cluster-cert operation; make `certificate_fingerprint` public).

## 2026-08-22 10:50 — Upstream issues filed
- [meigma/pyinfra-incus#20](https://github.com/meigma/pyinfra-incus/issues/20)
  "Support IncusOS targets: run the CLI on the controller against a named
  remote" — evidence: `_cli.py:75`/`:100` builds bare `["incus", *args]`;
  README lines 16-25 require the `incus` CLI + root on the target, which
  IncusOS structurally cannot provide. Proposes opt-in `remote=` threaded
  through facts/ops (prefix preferred over `INCUS_REMOTE` so it cannot leak),
  composing with the existing `?target=` member scoping in `facts.py:92`;
  keeps current behaviour default; asks the argv-quoting contract to cover the
  remote value. Flags `/os/1.0` facts/ops as the natural follow-up and records
  the `incus query` constraint (no stdin form → literal `--data`, needs an
  explicit carve-out in the "nothing secret in argv" contract).
- [meigma/pyinfra-incus#21](https://github.com/meigma/pyinfra-incus/issues/21)
  "Missing cluster certificate support" — trust store vs `cluster.crt` table;
  asks for `operations.cluster_certificate` with fingerprint-diff idempotency
  against `facts.Server`'s `environment.certificate_fingerprint`, the
  all-members-Online precondition, explicit no-rollback docs, no-restart
  behaviour, and a file-path key contract (the CLI takes paths, so the stdin
  contract cannot apply) with the SOPS→`mktemp`→`trap rm` pattern as the
  recommended shape. Also asks to make `_control_plane.certificate_fingerprint`
  public, with the two findings from reusing it: lenient base64 decoding needs a
  `0x30 0x82` DER guard, and fingerprints should be colon-stripped/lowercased
  before comparison.

Both labelled `enhancement`; #21 notes it depends on #20 for IncusOS fleets but
is independently useful for SSH-managed clusters. T49 updated with both links.
