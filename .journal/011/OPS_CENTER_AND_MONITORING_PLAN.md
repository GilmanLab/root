# Operations Center, the Incus web UI, and monitoring — plan (session 011)

Status: proposal. Nothing deployed. Live evidence gathered 2026-08-21 against the
running 4-node cluster; Track A step A0 and the UI check were executed as
throwaway spikes (see "Evidence").

## Headline

Clarified intent (2026-08-21): the ask was a **Proxmox-style GUI over Incus**,
not time-series monitoring.

**That GUI already exists and is already running on the cluster** — the built-in
**Incus web UI at `https://<member>:8443/ui/`** (version `7.3-ui-0.21`, shipped
by the IncusOS `incus` application). Verified live: instance list, cluster
members with roles and memory, networking/ACLs/IPAM, storage pools/volumes/
buckets/custom ISOs, images, profiles, projects, operations, warnings, server
settings, usage, "Create instance", and a per-node **Incus OS** panel
(Overview / Applications / Debug / Services / System) for IncusOS itself.
Nothing needs deploying; it needs a browser credential and a DNS name.

**Operations Center is a different layer and cannot replace it.** OC's instance
data is read-only inventory: the v0.8.1 API exposes only `GET
/1.0/inventory/instances[/{uuid}]` plus `POST …/:resync`. There is **no create,
edit, start/stop, console, snapshot or migrate operation for instances**. OC
mutates *servers and clusters* (power, evacuate, factory-reset, update channel,
BMC, cluster create/add/remove members, tokens, seeds). It is a fleet/datacenter
manager, not a hypervisor GUI.

So there are three separable pieces of work, and they should not be coupled:

- **Track 0 — use the GUI you already have** (below): browser credential + DNS.
  Hours, not days.
- **Track A — monitoring** (history, dashboards, alerts): Prometheus + Grafana
  against each member's existing `/1.0/metrics`. Zero IncusOS changes needed.
- **Track B — Operations Center** (T44): fleet control plane — multi-cluster
  inventory, token provisioning, update orchestration, BMC. Valuable later,
  currently gated on a one-way door.

## Track 0 — make the built-in UI usable (do this first)

Two gaps, both real, both fixable in one sitting:

1. **No DNS.** The mirrored `glab.lol` zone has no A record for any lab host
   (`dig nas01.glab.lol @10.10.10.1` returns nothing; the zone's SOA is AWS).
   Records must be authored in the Route53 **private** zone in `GilmanLab/aws`
   (sole writer); gw01 re-fetches the zone every 1 min and CoreDNS reloads
   every 30 s, so changes land in the lab in ≤90 s.
2. **Certificate names.** All four members present ONE shared certificate
   (`cluster.crt`) whose only SAN is `DNS:nas01.glab.lol` — no IP SANs, no
   lab0N names. So browsing by IP always warns, and even after DNS exists only
   `nas01` would validate. Fix: mint a new shared cert with every name + IP and
   push it with `incus cluster update-certificate`, which fans it to all
   members and live-swaps the API/cluster/metrics listeners without a restart.
3. **Browser credential.** The UI itself generates one — no copying of the
   `bootstrap-admin` key. Its "Set up TLS login → Generate" page creates an
   RSA-2048 / 1000-day cert in a web worker and hands back `incus-ui.crt` plus a
   password-protected `incus-ui.pfx` (3DES, specifically so macOS Keychain will
   import it). Enrollment uses a trust token.

### Runbook

**Phase 1 — DNS (`GilmanLab/aws`, PR).** Blocked on `aws sso login --profile
lab-admin` (the token is currently expired).

```sh
cd aws && git fetch origin --prune
wt switch --create --base origin/master --no-cd --format=json feat/lab-host-dns
```

In `aws/lab-foundation`, add a `lab_host_records` map plus a `for_each`
`aws_route53_record` in the private zone (the zone's owner root; `aws/keycloak`
is the precedent for a root creating its own A record):

| Name | Value |
| --- | --- |
| `nas01.glab.lol` | 10.10.10.14 |
| `lab01.glab.lol` | 10.10.10.11 |
| `lab02.glab.lol` | 10.10.10.12 |
| `lab03.glab.lol` | 10.10.10.13 |
| `incus.glab.lol` | all four (round-robin cluster entry point) |

TTL 300. Optional extras: `gw01` 10.10.10.1, `sw-core01` 10.10.10.2,
`sw-mgmt01` 10.10.70.2. Plan must be adds-only, then squash-merge and apply.
Verify: `dig +short nas01.glab.lol @10.10.10.1` inside 90 s.

**Phase 2 — cluster certificate (live cluster, gated).**

Preflight, all verified 2026-08-21:

- `incus cluster list nas01:` → all four ONLINE (**required**: a new private key
  is refused unless every member is reachable).
- `incus admin os system fallback-listener show nas01:` → `bootstrap-admin` is
  trusted, `active: false`. Recovery path intact.
- Current fingerprint `ea493033…9a0f`, SAN `DNS:nas01.glab.lol` only.

**One-way risk, stated plainly:** the current cert's private key lives only on
the nodes and cannot be exported, so there is no rollback to it. Incus does a
best-effort rollback if fan-out fails mid-flight; if that fails the recovery is
console-level (IncusOS lost-certificate emergency procedure: recovery key,
Secure Boot off, `patch.global.sql`). Do this with AMT/PiKVM to hand.

### Making Phase 2 GitOps rather than a hand command

Two mechanisms do **not** exist, so they are off the table (both checked):

- **No IncusOS seed field for the server certificate.** The `incus` seed carries
  only `incusapi.InitPreseed` (`incus-osd/api/seed/incus.go`), and
  `GetServerCertificate` reads `cluster` then `server` from the app's own data
  dir (`app_incus.go:203`). The cert cannot be baked into the image recipe, so a
  rebuilt node cannot come up already presenting it.
- **No OpenTofu resource for it.** `terraform-provider-incus` ships
  `incus_certificate` (trust store: `client`/`metrics` types) and `incus_server`
  (server *config keys*). Neither touches `cluster.crt`. So there is no
  `tofu apply` path for the certificate itself.

What is left is the lab's existing bare-metal GitOps shape: **declare it in git,
converge it with a re-runnable idempotent tool**. That tool already exists and
already owns cluster day-2 state — `fleet/cluster/` (`fleet_cluster`, pyinfra,
facts → diff → `incus` commands, `moon`-invoked, unit-tested). Adding the
certificate there keeps the rule from session 010 intact: *all cluster day-2
config flows through `fleet_cluster`, no ad-hoc commands.*

Shape of the change (mirrors the existing storage/network trio):

- `facts.py`: `IncusServerCertificate` — read `environment.certificate_fingerprint`
  from `incus query <remote>:/1.0` (live value today: `ea493033…9a0f`).
- `operations.py`: `cluster_certificate(...)` — compute the SHA-256 fingerprint
  of the desired PEM, no-op when it matches, otherwise emit
  `incus cluster update-certificate <remote>: <crt> <key>`. Guard: refuse to run
  unless every member is ONLINE (the API rejects a new key otherwise), reusing
  the existing `IncusClusterMembers` fact.
- `deploys/certificate.py`: declares the desired cert for `REMOTE`.
- `config.py`: the SAN list — `incus`, `nas01`, `lab01`-`lab03` under
  `glab.lol`, plus `10.10.10.11-.14` and loopback — so the names live in git and
  adding a node is a git diff.
- Tests alongside `test_operations.py`: fingerprint match → no-op; mismatch →
  exactly one command; member offline → refuse.

Two candidate sources for the certificate material, same convergence code:

**Option A — self-signed, escrowed (recommended now).** Cert + key generated
once (already staged at `/tmp/monspike/incus-cluster.{cnf,crt,key}`: P-384, 10
years, `CN=incus.glab.lol`, the five SAN names + `10.10.10.11-.14` + loopback,
fingerprint `27:86:A3:A9:…:E0:10`), escrowed in `GilmanLab/secrets` as
`fleet/cluster/tls.sops.yaml` (durable generated recovery material, the ADR-0003
exception), and read by `fleet_cluster` at converge time exactly as the pyinfra
projects already read SOPS material. Reproducible: rebuild a node, re-run the
converge, same cert. No external dependency, no credential in cluster config,
keeps the IP SANs that IP-based scraping and `incus remote` rely on. Cost:
rotation is a file swap plus a converge run, not automatic.

**Option B — ACME, fully declarative (target state).** `incus_server` (tofu) or
`fleet_cluster` sets `acme.agree_tos`, `acme.email`, `acme.domain`,
`acme.challenge=DNS-01`, `acme.provider=route53`, `acme.provider.environment`.
The leader then issues and renews on its own — daily check, renew under 30 days
— and fans the result to all members. Git holds intent only; no cert or key is
ever escrowed or pushed by hand. Costs, all real: a public CA cannot sign
private-IP SANs (everything must move to names — `incus remote`, Prometheus
targets, `fleet_cluster`'s `REMOTE` address); the five hostnames land in
Certificate Transparency logs; a static AWS credential scoped to the delegated
`acme.glab.lol` zone has to live in replicated Incus cluster config; and each
name needs its own `_acme-challenge.<host>.glab.lol` CNAME at Cloudflare, which
is a manual step today because no Cloudflare provider is in the stack (the
`aws/keycloak` precedent did exactly this once, by hand).

Recommendation: **A now, B when the CNAME delegation and credential story are
worth automating** — the convergence code is identical, so B is a config swap
plus deleting the escrowed material. A third path, issuing from the lab's own
root CA, remains the eventual best answer and lands in the same place.

Whichever source: after convergence, update the monitoring spike's `ca_file`
(and drop `server_name` under option A, since IP SANs then cover IP scraping).

The one irreducibly manual step is client-side, not lab state: trusting the new
cert once on the workstation —
`sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain incus-cluster.crt`
(not needed at all under option B).

**Phase 3 — browser identity. DEFERRED** (Josh, 2026-08-21: certs/DNS first,
auth later). Recorded for when it comes back up:

1. `https://incus.glab.lol:8443/ui/` → **Set up TLS login → Generate**, give a
   **non-empty** password (empty-password PFX import fails on macOS), download
   `incus-ui.crt` + `incus-ui.pfx`.
2. Keychain Access → **login** keychain → File → Import Items → `incus-ui.pfx`;
   restart the browser. Do **not** mark the client cert "Always Trust" — Incus
   trusts its fingerprint, not a chain.
3. From a terminal still authenticated as `bootstrap-admin`:
   `incus config trust add nas01: incus-ui` → prints a token. In Incus 7.3 the
   name is positional, the token is single-use, and `core.remote_token_expiry`
   defaults to no time expiry. Omit `--restricted` for full UI admin.
4. UI → `/ui/login/certificate-add` → select **Incus UI** → paste token → Import.
5. `incus config trust list nas01: -c nftrep` and record both fingerprints.
   Keep `bootstrap-admin` as break-glass; the browser identity can be revoked
   alone with `incus config trust remove nas01: <fingerprint>`.

### Deliberately not doing (yet)

- **Public ACME.** Incus 7.3 does support it (`acme.domain`, `acme.email`,
  `acme.challenge=DNS-01`, `acme.provider`, `acme.provider.environment`; lego is
  shipped whole, so Route53/Cloudflare providers are available, and the lab
  already delegates `acme.glab.lol` for DNS-01). Rejected for now: a public CA
  cannot sign private-IP SANs (breaks IP-based `incus remote` and scraping), lab
  hostnames would land in Certificate Transparency logs, and cloud credentials
  would sit in replicated cluster config. Issuance/renewal is leader-only, daily,
  renewing under 30 days.
- **Lab CA issuance.** The eventual right answer (root CA already exists in
  `GilmanLab/aws`), but no intermediate/issuance path is built — the same parked
  question as ADR-0004's pinned device CA. Migration later is a re-run of
  `incus cluster update-certificate` with a leaf + chain.
- **OIDC.** Once Zitadel serves (T36): `oidc.issuer`, `oidc.client.id`,
  `oidc.claim`. Caveat: OIDC alone grants **every** authenticated IdP user full
  access; restricting it needs OpenFGA plus `authorization.client.oidc=openfga`.

What the UI does **not** give, and why Track A still matters: no history beyond
the live view, no dashboards over time, no alerting, and no host-level
CPU/memory/disk/temperature trend. It answers "what is the cluster doing right
now", not "what happened at 03:00" or "tell me when a pool degrades".

A convenience trap worth naming: for verification I ran a local reverse proxy
(`/tmp/monspike/uiproxy.ts`, port 8099) that attaches the client cert so any
browser can load the UI. That is an unauthenticated bypass of Incus's auth on
localhost — fine as a throwaway, never a lab service.

## Why Operations Center is neither the GUI nor the monitor

- **Instances are read-only inventory.** Enumerating every `swagger:operation`
  in v0.8.1 `internal/api/*.go`: instances/networks/profiles/projects/storage/
  images expose only `GET …` and `POST …/:resync`. Mutating operations exist
  only for *servers* (`:reboot`, `:poweroff`, `:evacuate`, `:factory-reset`,
  `system/update`, `bmc/:server-power-on|off|restart`, `system/network`,
  `system/storage`), *clusters* (`POST`, `:add-servers`, `:remove-servers`,
  `:update`, `:bulk-update`), channels, updates, tokens and seeds. No instance
  create/start/stop/console/snapshot/migrate anywhere in the API.
- OC v0.8.1 (2026-08-07, pre-1.0, 40 open issues) is inventory + provisioning +
  update channels + a warning ledger. Server state is refreshed by a **5-minute
  reachability/version poll**. No time series, no utilization history, no alert
  rules, no notification routing.
  <https://github.com/FuturFusion/operations-center/blob/v0.8.1/doc/reference/server.md>
- The released OpenAPI has **no metrics/alerting surface**, and the daemon wires
  **no `/metrics` handler** — the generated `*_prometheus_gen.go` middleware is
  dead code in v0.8.1. Verified in the local module cache
  (`$(go env GOMODCACHE)/github.com/!futur!fusion/operations-center@v0.8.1`):
  `grep -rn "promhttp\|/metrics" cmd internal` → no matches.
- Adoption of an already-formed cluster is **not supported in the released
  surface**: servers are expected to come from OC-seeded images, and clusters
  are *created* from registered standalone servers. No import/adopt endpoint
  exists.
  <https://github.com/FuturFusion/operations-center/blob/v0.8.1/doc/reference/cluster.md>
- Registration is a **one-way door**. `incus-osd`'s OC provider returns
  `ErrDeregistrationUnsupported` — "At the moment, deregistration is not
  supported for Operations Center"
  (`incus-osd/internal/providers/provider_operations_center.go:201`, vendored at
  `~/code/componere/incusos-builder/reference/incus-os`). Undo = factory reset /
  reinstall.
- Registration also **hands the update channel to OC** (`GetOSUpdate`,
  `GetApplicationUpdate`, `GetSecureBootCertUpdate` all resolve through OC),
  which collides with the pinned-release-in-git model (T25/T26). There is no
  documented observation-only registration.

Conclusion: do not point production nodes at OC to get visibility. That trade is
irreversible and buys the wrong thing.

## What the cluster already gives us (verified live today)

- Each member serves Prometheus text at `https://<member>:8443/1.0/metrics`
  using the **already-trusted `bootstrap-admin` client certificate**. All four
  return HTTP 200. `core.metrics_address` does **not** need to be set; the
  existing `core.https_address` listener already serves it.
- IncusOS ships `prometheus-node-exporter` (localhost:9100) and Incus 7.3 merges
  its output into `/1.0/metrics`. nas01 returns **~3300 `node_*` series + ~98
  `incus_*` series**, including:
  - `node_zfs_zpool_state{zpool,state}` — `data` and `local` both `online`
  - `node_hwmon_temp_celsius` — NVMe and board sensors (28-55 °C observed)
  - `node_disk_*` (550), `node_network_*` (431), `node_cpu_*` (408),
    `node_systemd_*` (759), `node_filesystem_*` (96), `node_pressure_*`
  - `incus_storage_pool_{size,used}_bytes`, `incus_warnings_total`,
    `incus_operations_total`, per-instance CPU/memory/network/disk
- All members present the **shared cluster certificate** (CN
  `root@nas01.glab.lol`, SAN `DNS:nas01.glab.lol` only — no per-member IP SANs).
  A scraper must therefore pin `server_name: nas01.glab.lol` with the cluster
  cert as CA for every target. This is exactly the Incus-documented pattern.
- Per-member semantics: a member reports only the instances running on it, so
  all four members are scrape targets. <https://linuxcontainers.org/incus/docs/main/metrics/>

Off-node signals that exist but are **not** in the metrics stream (they need an
authenticated JSON poll of `/os/1.0/...`, i.e. a small exporter later):

| Signal | Source |
| --- | --- |
| Pending OS update / `needs_reboot` | `/os/1.0/system/update` (live: `status: "Update check completed"`, `needs_reboot: false`) |
| Per-drive SMART, degraded vdev detail, scrub errors | `/os/1.0/system/storage` (live: pools `data`/`local` = `ONLINE`) |
| Secure Boot / TPM / encryption state | `/os/1.0/system/security` |
| LACP/LLDP link state (relevant to T48) | `/os/1.0/system/network` |
| Remote syslog config (currently **unset** on all nodes) | `/os/1.0/system/logging` |

## Track A — monitoring (recommended, start now)

### A0 — throwaway laptop spike (DONE)

Prometheus + Grafana in Docker on the workstation, scraping all four members
with the existing client cert. Executed end to end today; both dashboards render
live data (see Evidence). Config lives in `/tmp/monspike` — deliberately
disposable, nothing committed, no lab change.

What A0 already taught us:

- **Grafana dashboard 1860 ("Node Exporter Full") is the useful one** and works
  unmodified: `nas01` shows CPU 13.4%, RAM 11.7% of 29 GiB, 24 cores, uptime
  1.2 days, per-filesystem usage of every Incus storage-pool dataset, and
  per-NIC traffic broken out by `mgmt` / `fast` / `fast30` / `incusbr0` / veths.
  Zero "No data" panels. The `node_uname_info` `nodename` label carries
  `nas01.glab.lol` … `lab03.glab.lol`, so the dashboard's node picker works as-is.
- The **official Incus dashboard 19727** also renders (instance CPU/memory/net,
  project rollups), but it is instance/project-centric and near-empty with one
  container. It needs `job`/`project`/`name` template variables set, and its
  datasource placeholder is `${DS_INCUS}` (not `${DS_PROMETHEUS}`) — a
  provisioning gotcha worth remembering.
- **Do not relabel `instance`.** Rewriting it (e.g. to `node-14`) silently breaks
  every community dashboard, which keys `$node` on `instance` = `ip:port`.
- TLS shape that works: `ca_file` = the cluster cert, `server_name:
  nas01.glab.lol` for all four targets, client cert + key. Scrape cost 0.11-0.21 s
  per member, ~3300 series each; the endpoint self-caches for 8 s.

### A1 — make it permanent: `mon01`

- One system container `mon01` running Prometheus + Grafana (+ Alertmanager),
  precedent: the `meshcommander` Debian-trixie container already on nas01.
- **Placement recommendation: `lab03`** (database-standby, expendable-by-design)
  with the TSDB on that node's `data` pool. Retention 30d.
- Reachability: VLAN 10, so Josh's workstation reaches the UI directly
  (`gw01` `WAN_FORWARD` rule 10 permits home → lab wholesale). No new firewall
  rules.
- Provisioning path: OpenTofu Incus provider root in `GilmanLab/fleet` — this is
  the already-decided mechanism for pet workloads (VISION T32), and fleet is
  already the home of Incus runtime config.
- Credential: mint a dedicated **restricted, `metrics`-type** certificate
  (`incus config trust add-certificate --type metrics`) instead of reusing
  `bootstrap-admin`; escrow under `GilmanLab/secrets`. Converge via the
  `fleet_cluster` pyinfra project so it stays a git-driven change.

**Accepted blind spot:** a scraper on the cluster dies with the cluster. Cover it
with A2's dead-man's switch, and treat `mon01` as deliberately disposable — when
the Talos management cluster exists (T32), monitoring moves to
`kube-prometheus-stack` and `mon01` is deleted.

**Alternative worth a ruling:** host the scraper on `sandbox01` instead, which
survives total cluster loss. Cost: a new `gw01` rule permitting
`10.10.40.10 → 10.10.10.11-14:8443`, which dents the "sandbox never initiates to
management" invariant. Recommendation: keep the invariant, accept A1 as
disposable — but this is Josh's call.

### A2 — alerting

- Alertmanager in `mon01`; notification egress is already permitted
  (`MGMT_FORWARD` rule 40 allows internet).
- Minimum rule set worth writing by hand (no official Incus rule bundle exists):
  target `up == 0`, `node_zfs_zpool_state{state!="online"} == 1`,
  `node_filesystem_avail_bytes` low, `node_hwmon_temp_celsius` high,
  `incus_warnings_total > 0`, member absent from cluster.
- **External dead-man's switch** (healthchecks.io / Grafana Cloud free tier)
  pinged by Alertmanager so "everything is down" is itself an alert.

### A3 — logs (optional, later)

- Set `/os/1.0/system/logging` syslog target on all four nodes (currently empty)
  via a new `fleet_cluster` deploy module, plus Incus's own `loki`/`syslog` log
  targets for lifecycle/audit events.
- Receiver: Loki (or plain syslog) in `mon01`. Only worth doing once there are
  workloads whose logs matter.

### A4 — coverage gaps to close deliberately, not now

Small polling exporter for the `/os/1.0` facts table above (update/reboot state,
SMART, degraded vdevs, link state). Then the rest of the lab, which has **no
monitoring at all today**: `gw01` (VyOS), `sw-core01` (RouterOS has a Prometheus
surface), `sw-mgmt01`, `pikvm01`, and the UPS (T04, still unwired).

## Track B — Operations Center spike (T44), decoupled

What OC would actually buy the lab: one inventory/UI across servers and clusters,
token-based provisioning of new machines, centrally controlled (air-gap-capable)
IncusOS update channels with rolling updates, and BMC integration. That is a real
answer to "we bought another machine — how does it get online quickly?", and it
is complementary to Track A, not a substitute.

Costs on the table: pre-1.0, one-way registration, OC owns the update channel,
and OC's own state (SQLite + cached images) becomes something to back up.

Deployment shape is already fully supported by the lab's existing tooling:

- OC runs as an **IncusOS application** (`operations-center`), one primary
  application per machine — so it is a dedicated appliance, not a cluster
  member. HTTPS 8443 on IncusOS; needs ≥1 trusted client cert in its seed.
- `incusos-builder` **already supports the `operations-center` seed section**
  (`internal/config/schema.go:72`, plus e2e tests) — so an OC appliance image is
  `nodes/<name>/config.yaml` in `GilmanLab/fleet` with the same pinned recipe.
  No new tooling.

Proposed spike, fully self-contained and production-safe:

1. On `sandbox01` (VLAN 40, vanilla Incus, no firewall changes): build and boot
   an **IncusOS VM running the `operations-center` application** plus **two
   throwaway IncusOS VMs running Incus** as guinea-pig servers.
2. Test in order: (a) token registration of a fresh server, (b) cluster
   *creation* from two registered servers, (c) the real question — form a
   cluster by hand first, then switch the provider on both members and see
   whether OC represents them as a cluster or as two orphan servers.
3. Ask upstream (issue/forum) for the two things the docs do not answer:
   is importing an existing cluster on the roadmap, and is observation-only
   registration possible without ceding the update channel?
4. Rule: adopt OC for the *next* machine onward, adopt it for the whole fleet
   (accepting a reinstall of the four nodes), or defer again with a recorded
   reason.

Do not switch any production node's provider until step 3 has an answer.

## Open questions for Josh

0. UI credential: export the existing `bootstrap-admin` key as PKCS#12 into the
   keychain now, or wait for Zitadel/OIDC (T36) and live with the proxy shim in
   the meantime?
1. Monitoring placement: `mon01` on the cluster (keeps VLAN 40 isolation) vs.
   `sandbox01` (survives cluster loss, needs one firewall rule)?
2. Is a system container acceptable for `mon01`, or does the "VM isolation
   preferred" stance apply even to internal tooling?
3. Alert delivery target — email, Pushover, ntfy, something else?
4. Is the OC spike worth doing now, or does it wait until the Talos management
   cluster and CAPI work land?

## Immediate next actions

- [ ] Track 0: add `nas01` (+ `lab01`-`lab03`, `gw01`) A records to the Route53
      private zone in `GilmanLab/aws`; confirm gw01's CoreDNS mirror picks them up.
- [ ] Track 0: import a browser client credential, then open
      `https://nas01.glab.lol:8443/ui/` and stop using the localhost proxy.
- [ ] Decide whether A1 ships dashboard 1860 + a hand-built IncusOS/ZFS panel set
      (19727 adds little until real workloads exist).
- [ ] Decide placement (question 1) and alert target (question 3).
- [ ] Land A1: tofu root in `GilmanLab/fleet`, metrics cert via `fleet_cluster`,
      escrow in `GilmanLab/secrets`.
- [ ] Land A2 rules + dead-man's switch.
- [ ] Update T44 in `VISION.md` with the adoption/one-way-door findings, and add
      a tracker item for lab-wide monitoring coverage (A4).

## Evidence

Commands run against the live cluster on 2026-08-21 (read-only):

```text
incus query nas01:/os/1.0/system/provider      -> {"config":{"name":"images"},"state":{"registered":false}}
incus query nas01:/os/1.0/system/update        -> channel stable, check 6h, auto_reboot false, needs_reboot false
incus query nas01:/os/1.0/system/logging       -> syslog address "" (unset)
incus query nas01:/os/1.0/system/storage       -> pools data=ONLINE (2 devices), local=ONLINE (1)
incus info nas01:                              -> Incus 7.3, IncusOS 202608201218, 4 members
curl --cert/--key .../1.0/metrics on .11-.14   -> 200; 3286-3301 node_* series each
curl .../ui/                                   -> 200, "Incus UI", version 7.3-ui-0.21
dig nas01.glab.lol @10.10.10.1                 -> NXDOMAIN-equivalent (zone has no lab A records)
openssl s_client 10.10.10.11/.14:8443          -> one shared cert, SAN DNS:nas01.glab.lol only
OC v0.8.1 swagger:operation enumeration        -> inventory = GET + :resync only
```

Throwaway Prometheus (Docker, `/tmp/monspike`, port 9099), scraping all four
members with `ca_file=cluster.crt`, `server_name=nas01.glab.lol`, and the
existing client cert:

```text
node-14 up  scrape=0.110s      ZPOOLS_ONLINE  all four members = 2 pools online
node-11 up  scrape=0.203s      MAXTEMP        44.0 / 52.0 / 55.0 / 49.5 °C
node-12 up  scrape=0.206s      MEM_PCT        11.7 (nas01) / 2.4 (labs)
node-13 up  scrape=0.205s      node_uname_info nodename=nas01..lab03.glab.lol
```

Grafana (Docker, port 3009, anonymous admin, provisioned datasource + both
dashboards) rendered against that Prometheus:

```text
/d/rYdddlPWk/node-exporter-full  var-node=10.10.10.14:8443  -> 0 "No data" panels
   CPU busy 13.4% · sys load 37.5% · RAM 11.7% of 29 GiB · 24 cores · uptime 1.2d
   root FS 3.8% of 24 GiB · per-pool dataset filesystems · per-NIC mgmt/fast/fast30
/d/bGY-LSB7k/incus  var-job=incus,var-project=default,var-name=meshcommander
   -> renders; project CPU/memory series present, per-instance counters at ~0
```

Reproduce (both containers are running now; they are throwaway):

```sh
docker run --rm -p 9099:9090 -v /tmp/monspike:/etc/prometheus:ro \
  prom/prometheus:latest --config.file=/etc/prometheus/prometheus.yml
docker run --rm -p 3009:3000 -e GF_AUTH_ANONYMOUS_ENABLED=true \
  -e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin -e GF_AUTH_BASIC_ENABLED=false \
  -v /tmp/monspike/grafana/provisioning:/etc/grafana/provisioning:ro \
  -v /tmp/monspike/grafana/dashboards:/var/lib/grafana/dashboards:ro \
  grafana/grafana:latest
```

(An early CPU-utilization query ran inside its own 2-minute rate window and read
~80% busy; that was a measurement artifact, not a busy cluster.)

Research reports: `history://OpsCenterCaps`, `history://IncusObservability`.
