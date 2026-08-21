# OpenTofu management architecture for `sw-core01`

Produced 2026-08-20 by a software-architect agent from live device state
(session 008 NOTES) and the v2 design docs. Status: PROPOSED — open questions
below need user rulings before execution.

## Decision summary

| Question | Decision |
| --- | --- |
| Repo | `GilmanLab/networking`, new `routeros/sw-core01/` OpenTofu root; one root per device |
| State | Reuse `s3://glab-lab-tfstate-186067932323`, key `networking/routeros/sw-core01.tfstate`, S3 native locking |
| Transport | REST over `www-ssl` (`hosturl = "https://10.10.10.2"`) |
| Auth | Dedicated `svc-tofu` user in a custom `tofu-svc` group (`read,write,rest-api`); `admin` becomes break-glass only |
| TLS | Re-minted device self-signed cert (`CN=sw-core01`, `SAN IP:10.10.10.2`), public cert committed and pinned via `ca_certificate`; never `insecure=true` |
| Credential | `GilmanLab/secrets` → `network/sw-core01/terraform.sops.yaml`; injected as `ROS_*` provider env vars at plan/apply, never a declared TF variable |
| Adoption | `import` blocks adopt everything v2 keeps; the bootstrap runbook purges everything v1 abandons (defconf bridge, VLANs 30/50/60); verified by `/export` diff |
| Ops model | Operator-triggered `just plan` / `just apply` from workstation (gw01 precedent); CI is offline-only (`fmt`/`validate`) — no live plan from GitHub-hosted runners |
| Docs | Update address plan (static-vs-reservation), design doc config-source paragraph, new runbook, new ADR-0004 |

## 1. Repo and root placement

**Decision: `GilmanLab/networking`, directory `routeros/sw-core01/`, one root per device.**

The v2 design states each network device has "one version-controlled configuration source" and names `GilmanLab/networking` as gw01's home. The switch's configuration source belongs beside it — the networking repo is the identity boundary for on-prem network device config. `GilmanLab/aws` is the wrong home despite owning the tofu conventions: its identity is the lab AWS account (the `network/tailscale` root there is SaaS/tailnet control plane, not an on-prem device), and putting a switch there splits network-device sources across two repos. A new repo adds CI/moon/secrets plumbing for one directory's worth of content.

**One root per device**, not one root for all RouterOS devices: independent state files mean independent blast radius, independent credentials, and a plan against `sw-core01` can never touch `rtr01`. When `rtr01` or the CCR2004 come under management they get sibling roots (`routeros/rtr01/`); a shared local module (`routeros/modules/…`) is created only when real duplication exists across ≥2 device roots — not before.

The root copies the `GilmanLab/aws` per-root conventions verbatim: per-root `Justfile` (`check`/`init`/`plan`/`apply`), partial S3 backend, committed `.terraform.lock.hcl`, per-root `.gitignore` (`.terraform/`, `tfplan`). A thin moon task in `networking/moon.yml` (`routeros-check`, `runInCI: true`, shelling to `just -f routeros/sw-core01/Justfile check`) wires it into the existing `check` pipeline; `routeros-plan`/`routeros-apply` are `runInCI: false` operator tasks, mirroring `vyos-sync`.

Rejected: `GilmanLab/aws` (repo identity mismatch); new repo (plumbing overhead, splits network sources); single multi-device root (shared blast radius, coupled applies).

## 2. State backend

**Decision: reuse `glab-lab-tfstate-186067932323`, key `networking/routeros/sw-core01.tfstate`.**

The bucket exists, is encrypted, and every existing root uses partial backend config with `use_lockfile = true` (S3 native locking) and `GLAB_AWS_STATE_BUCKET` supplied by the operator's `.envrc`. Keys in the aws repo mirror repo paths (`security/pki/root-ca.tfstate`); because this root lives in a different repo, prefix by repo name — `networking/routeros/sw-core01.tfstate` — so `network/tailscale.tfstate` and future networking-repo keys can never collide.

```hcl
# backend.tf
terraform {
  backend "s3" {
    key          = "networking/routeros/sw-core01.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
```

- **Operator creds**: `AWS_PROFILE=lab-admin` (SSO), exactly as the aws roots' READMEs prescribe.
- **CI creds**: none. CI runs `tofu init -backend=false` only (see §7), so no OIDC role, no state access, no device access from GitHub.
- Switch state contains no secrets (provider config is not persisted in state), so no extra state-encryption ceremony beyond the bucket's SSE.
- Availability coupling is acceptable: S3 state is reached over the internet from the workstation; if the lab network is down you cannot reach the switch either, and recovery in that regime is the console/runbook path, not tofu.

Rejected: local state in-repo (no locking, no durability); a new bucket (needless duplication of a solved bootstrap).

## 3. Provider transport, auth, and certificates

### Transport: REST over `www-ssl`

`hosturl = "https://10.10.10.2"` selects the REST client. REST is the provider's default and primary path, it is already enabled and reachable on the live device, it is TLS-native, and it avoids enabling an additional service (binary `api`/`apis` state on the device is unknown and should be **disabled** in v2 hardening). Use the IP, not a DNS name — switch management must not depend on gw01's resolver.

Rejected: binary API (`apis://`) — second service to enable and harden, no functional advantage for this provider.

### Auth: dedicated service account

Bootstrap creates (manually, see §8):

- Group `tofu-svc`, policies `read,write,rest-api` — no `ssh`, `ftp`, `winbox`, `policy`, `password`, `sensitive`. Omitting `policy`/`password` means the account cannot manage users, which is deliberate (§4). If a specific resource read fails without `sensitive`, add it then and note it in the runbook.
- User `svc-tofu`, group `tofu-svc`, `address=10.10.10.0/24,192.168.1.0/24` (management subnet + routed home sources).

Be honest about the threat model: a `write`-capable account on a switch is near-admin. The value of the split is auditability (log lines name `svc-tofu`), revocability (rotate/disable without touching break-glass), and blast-radius on the credential (address-restricted, no interactive services) — not privilege reduction. `admin` keeps a separately stored password and becomes break-glass only.

Rejected: reusing `admin` (no rotation independence, no audit distinction, interactive+API on one credential).

### Certificate strategy: re-minted self-signed cert, pinned in-repo

The live cert is self-signed with the v1 name `crs309.mgmt.lab.gilman.io` — wrong identity, and it already causes CN errors. Options considered:

- `insecure = true` — **rejected.** MITM-able management path, and it normalizes the worst habit for every future RouterOS device.
- Pin the existing cert — **rejected.** Pins the wrong identity; bootstrap must touch the cert anyway.
- Issue a leaf from the lab root CA (`security/pki/root-ca`) — **rejected for now.** The root-ca README explicitly reserves the KMS key for *intermediate* issuance ("Root certificate minting is an explicit operator action…"; hierarchy plan is root → Vault intermediate → SPIRE), and no device-PKI intermediate exists. Minting leaves straight off the root violates that stated policy for one switch's convenience.
- **Chosen:** during bootstrap, generate a fresh on-device self-signed cert `CN=sw-core01`, `SAN IP:10.10.10.2` (RouterOS `/certificate add … subject-alt-name=IP:10.10.10.2` + self-sign), bind it to `www-ssl`, export the public cert, commit it as `routeros/sw-core01/certs/sw-core01.crt`, and set `ca_certificate` to that file. A self-signed cert placed in the trust pool validates as its own one-element chain; this is explicit, reviewable trust-on-first-use with rotation = replace the committed file. Two things to **verify during bootstrap** (flagged, not fully groundable from docs): (a) the provider's Go TLS stack accepts the self-signed leaf-as-root arrangement, and (b) RouterOS emits the `SAN IP` such that hostname verification of `10.10.10.2` passes. If either fails, the documented fallback is issuing from the root CA per the rejected option, raised as an ADR amendment — not `insecure=true`.

When a device-PKI intermediate exists later, migrate all RouterOS roots to it in one change (swap `ca_certificate` to the committed `root_ca.crt`).

```hcl
# providers.tf
provider "routeros" {
  hosturl        = "https://10.10.10.2"
  ca_certificate = "${path.module}/certs/sw-core01.crt"
  # username/password from ROS_USERNAME / ROS_PASSWORD env — never variables
}
```

## 4. Credential handling

**Decision: SOPS file in `GilmanLab/secrets` at `network/sw-core01/terraform.sops.yaml`** (mirrors `network/tailscale/terraform.sops.yaml`; `network/` domain, standard `Repo`/`Scope` KMS encryption context). Keys: `username`, `password` for `svc-tofu`, plus `admin_password` (break-glass, never consumed by automation).

**Flow: provider-native `ROS_*` env vars, not `TF_VAR_*`.** The Justfile `plan`/`apply` recipes do:

```just
plan:
    test -n "${GLAB_SECRETS_DIR:-}" || { echo "Set GLAB_SECRETS_DIR…" >&2; exit 1; }; \
    export AWS_PROFILE="${AWS_PROFILE:-lab-admin}"; \
    export ROS_USERNAME="$(sops -d --extract '["username"]' "$GLAB_SECRETS_DIR/network/sw-core01/terraform.sops.yaml")"; \
    export ROS_PASSWORD="$(sops -d --extract '["password"]' "$GLAB_SECRETS_DIR/network/sw-core01/terraform.sops.yaml")"; \
    tofu plan -out=tfplan
```

This is a deliberate, narrow deviation from the tailscale root's `TF_VAR_` pattern, and strictly better here: the provider schema reads `ROS_USERNAME`/`ROS_PASSWORD` via env defaults at configure time, so the password is never a declared Terraform variable — it cannot appear in state, in `tofu plan` variable output, or in the saved `tfplan` artifact's recorded variable values. [INFERENCE] Saved plan files record the *written* provider config (attribute unset) and re-resolve env defaults at apply; plan-file internals not fully grounded, but the env-var path is a strict subset of the exposure of the `TF_VAR_` path in every case. Residual unavoidable exposure: process environment of the tofu process, and secrets held in memory during the run — same posture as gw01's in-memory rendering.

Corollary that shapes resource scope: **no `routeros_system_user` resources with passwords** — `password` on that resource lands in state, which we are keeping secret-free. See §5.

Rejected: `TF_VAR_` sensitive variables (value recorded in plan files); committed encrypted `.tfvars` (decrypt-to-disk step); 1Password/Bitwarden as source of truth (secrets repo is the established root of trust per ADR-0003).

## 5. Root layout and resource inventory

```
networking/routeros/sw-core01/
├── Justfile            # check / init / plan / apply / output / snapshot
├── README.md           # prerequisites, envrc vars, runbook pointer
├── .gitignore          # .terraform/, tfplan
├── .terraform.lock.hcl # committed, like every aws root
├── backend.tf          # §2
├── terraform.tf        # required_version >= 1.10; routeros provider pinned "~> 1.0"
├── providers.tf        # §3
├── ethernet.tf         # 9 adopted interfaces (factory_name), comments carry PHY-IDs
├── bridge.tf           # bridge + 8 ports + vlan rows 10/40
├── mgmt.tf             # mgmt-vlan10, 10.10.10.2/24, dns, default route
├── services.tf         # www-ssl on; www/ftp/telnet/api/api-ssl off; ssh/winbox restricted
├── system.tf           # identity, tofu-svc group
├── imports.tf          # OpenTofu import blocks — deleted after adoption apply
└── certs/sw-core01.crt # pinned TLS anchor (§3)
```

`just snapshot` is an extra recipe over the aws template: `ssh admin@10.10.10.2 '/export show-sensitive file=pre-apply'` + fetch, run before any apply (§9). It is why `ssh` stays enabled (restricted) in v2 services.

### Resource inventory

Interface naming decision: **keep factory names** (`sfp-sfpplus1..8`, `ether1`) and put roles + PHY cable IDs in comments. This matches the gw01 precedent (VyOS keeps `ethN`, mapping lives in the address plan), keeps chassis labels ↔ config trivially correlated, and — critically — avoids renaming `sfp-sfpplus8` (the management path) during migration. The v1 pet names (`to-vyos`, `LAB0x VM/SAN`, `spare-port1`) revert to factory names; RouterOS propagates renames to referencing config.

| # | Resource | Instance | Origin | v2 intent |
| --- | --- | --- | --- | --- |
| 1 | `routeros_interface_bridge` | `bridge-lab` | **import** | The single VLAN-filtered bridge (`vlan_filtering=true`). Name kept as `bridge-lab`; renaming the bridge under the live mgmt VLAN is churn with no functional gain (optional cosmetic later). |
| 2 | `routeros_interface_ethernet` ×9 | `ether1`, `sfp-sfpplus1..8` | **adopt** via `factory_name` (no import needed per provider pattern) | Names = factory; comments = `"lab01 SFP right (PHY-012)"` … `"gw01 trunk (PHY-002)"`. `ether1`: no role in v2 — proposed disabled with comment `"unused / emergency access"` (open question Q2). |
| 3 | `routeros_interface_bridge_port` ×8 | sfpplus1–8 on `bridge-lab` | **import** 5 (sfpplus1–4, 8), **create** 3 (sfpplus5–7 after defconf purge) | All `frame_types = admit-only-vlan-tagged`, `ingress_filtering = true` (matches live v1 lab ports). Ports 1–7 carry no VLANs yet — membership deferred per design doc. |
| 4 | `routeros_interface_bridge_vlan` ×2 | VLAN 10, VLAN 40 | **import** both | 10: tagged `sfp-sfpplus8` + `bridge-lab` (mgmt path). 40: tagged `sfp-sfpplus8` only — no other member yet; the row documents the trunk contract with gw01. Rows 30/50/60: purged by runbook, never imported. |
| 5 | `routeros_interface_vlan` | `mgmt-vlan10` | **import** | `interface=bridge-lab`, `vlan_id=10`. Name kept. |
| 6 | `routeros_ip_address` | `10.10.10.2/24` on `mgmt-vlan10` | **import** | Static (see docs decision D1). Defconf `192.168.88.1/24`: runbook purge. |
| 7 | `routeros_ip_dns` | singleton | manage (check whether provider requires import for settings resources during adoption plan) | `servers = 10.10.10.1`. |
| 8 | `routeros_ip_route` | `0.0.0.0/0 → 10.10.10.1` | **import** | Unchanged. |
| 9 | `routeros_system_identity` | singleton | manage | `sw-core01` (naming registry). |
| 10 | `routeros_ip_service` ×~7 | by name | **import** (by service name, per provider docs) | `www-ssl`: enabled, cert `sw-core01-tls`, `address = 10.10.10.0/24,192.168.1.0/24`. `ssh`: enabled, same restriction (snapshot path). `winbox`: restricted or disabled (open question Q3). `www`, `ftp`, `telnet`, `api`, `api-ssl`: disabled. |
| 11 | `routeros_system_user_group` | `tofu-svc` | **import** (created by bootstrap) | Non-secret; adopted so policy drift is visible. Marked in-code: changes here can cut tofu's own session. |
| — | `routeros_system_user` | — | **not managed** | Passwords would enter state; and tofu mutating its own login mid-apply is a self-lockout class of failure. Users are runbook-owned. |
| — | TLS certificate | `sw-core01-tls` | **not managed** | Chicken-and-egg: the provider needs the cert trusted before it can connect. Cert lifecycle is runbook-owned (§8). |
| — | NTP client | — | **deferred** | Time drift observed live, but time-service ownership is an explicit design-doc non-goal (open question Q4). |

### Adoption vs. purge rule

One consistent rule, stated in the runbook and the ADR:

- **Adopt** (via OpenTofu `import` blocks in `imports.tf`, reviewed as a plan, file deleted after the adoption apply): every object that exists today *and* appears in v2 desired state.
- **Purge** (manual runbook step, before/around the adoption applies): every v1 object with no v2 future — defconf `bridge`, its port rows (`ether1`, sfpplus5/6/7), `192.168.88.1/24`, VLAN rows 30/50/60, the legacy `crs309.mgmt.lab.gilman.io` cert. Import-then-destroy for these is state ceremony with no benefit; tofu never desired them.
- **Prove clean**: after cutover, `/export` from the device is diffed against an expected-shape export; any line tofu doesn't own must be explainable (users, cert, defaults). This closes the "unmanaged remnant lingers silently" gap that the purge rule opens.

**Drift detection** is `just plan` (refresh-only or normal): before every change, after any RouterOS upgrade, and ad hoc. No CI drift job — see §7.

## 6. Cutover sequence

Safety context: management rides in-band on VLAN 10 through `sfp-sfpplus8`; RouterOS has no commit-confirmed; Safe Mode is a terminal-session feature (console/SSH/Winbox) and **does not cover REST API changes**, so tofu applies get no automatic revert. The design compensates three ways: (1) the mgmt-path resources are *imported unchanged*, so no apply ever needs to modify them; (2) the defconf dissolution is entirely off the management path; (3) every phase starts from a downloaded backup + export.

**Key safety property: no step modifies `bridge-lab`, the sfpplus8 port row, the VLAN-10 row, `mgmt-vlan10`, `10.10.10.2/24`, or the default route. The management path is adopt-only.**

| Phase | Kind | Actions |
| --- | --- | --- |
| **P0 — Snapshot** | manual, per-run | `/system backup save` + `/export show-sensitive file=…`; download both off-box. Repeat before every later apply (`just snapshot`). |
| **P1 — Bootstrap auth/TLS** | manual, one-time (§8) | Service account, new cert, secrets repo entries, REST verification with pinned cert. |
| **P2 — Adopt** | tofu, one-time | `just init`; apply `imports.tf` import blocks (bridge, 5 port rows, VLAN rows 10+40, `mgmt-vlan10`, ip address, route, services, `tofu-svc`). The adoption plan must show **imports and in-place updates only — zero replacements**; any forced replacement on the mgmt path stops the migration for redesign. Delete `imports.tf` after. |
| **P3 — Low-risk convergence** | tofu apply | Identity → `sw-core01`; interface comments + v1 name reversions; service hardening (disable `www`/`ftp`/`telnet`/`api`/`api-ssl`, restrict `ssh`); DNS/route asserted. |
| **P4 — Purge v1 remnants** | manual runbook (SSH session **with Safe Mode engaged**) | Delete VLAN rows 30/50/60; delete defconf `bridge` + `192.168.88.1/24` (removes its port rows). Off the mgmt path; nas01's 10G link (port 7) drops its stray 192.168.88/24 L2 here — a fix, not an outage. |
| **P5 — Complete port set** | tofu apply | Create the three new `bridge-lab` port rows for sfpplus5/6/7 (tagged-only, no VLANs). `ether1` per Q2 decision. |
| **P6 — Verify + record** | manual | `just plan` → empty. `/export` diff vs expected. Link/VLAN checks per design doc verification list. Fresh post-cutover backup/export archived. Docs updates land (§9). |
| Optional dead-man switch for P4 | manual | `/system scheduler` entry (+10 min) re-adding a static emergency IP on `ether1`; removed on success. Offered, not required. |

Last-resort recovery: `admin` break-glass over SSH/webfig; RouterOS reset-button restore + backup file; serial console — CRS309 serial-port presence **not verified**; confirm physically before P4.

**Ongoing tofu-managed** (after P6): everything in the inventory's managed rows. **Permanently runbook-manual**: backups/snapshots, users and passwords, TLS cert lifecycle, RouterOS upgrades, factory-default recovery.

## 7. Operational model and CI

**Operator-triggered from the workstation, exactly like gw01.** `just plan` → review → `just apply` (applies the saved `tfplan`). Prerequisites: `AWS_PROFILE=lab-admin`, `GLAB_AWS_STATE_BUCKET`, `GLAB_SECRETS_DIR`, and network reach to `10.10.10.2`.

**CI on PR runs offline checks only**: `tofu fmt -check`, `tofu init -backend=false`, `tofu validate` (moon `routeros-check` task). GitHub-hosted runners have no route to `10.10.10.2`, and a plan against this provider *requires* the device (every read hits the REST API). Self-hosted or tailnet-connected runners were **rejected**: both put device write-credentials and network reach into CI to gain a read-only nicety, against the repo's established posture (CI never decrypts secrets, never contacts the device). Drift detection is an explicit operator duty. If the RouterOS estate grows, revisit with a dedicated read-only device account + tailnet runner as its own ADR.

`tofu test` with mock providers: skip until there's provider-independent logic worth testing.

## 8. Bootstrap runbook outline (one-time, from today's live state)

All steps run as `admin` over the already-reachable webfig/SSH at `10.10.10.2`:

1. **Snapshot**: `/system backup save name=pre-v2` + `/export show-sensitive file=pre-v2`; download both; archive outside the repo.
2. **Group**: `/user group add name=tofu-svc policy=read,write,rest-api`.
3. **User**: strong password; `/user add name=svc-tofu group=tofu-svc address=10.10.10.0/24,192.168.1.0/24`.
4. **Secrets**: write `network/sw-core01/terraform.sops.yaml` (`username`, `password`) in `GilmanLab/secrets`; rotate `admin`'s password and store as `admin_password` (break-glass).
5. **Certificate**: `/certificate add name=sw-core01-tls common-name=sw-core01 subject-alt-name=IP:10.10.10.2 days-valid=1095 key-usage=digital-signature,key-encipherment,tls-server`; `/certificate sign sw-core01-tls`; `/ip service set www-ssl certificate=sw-core01-tls`; export public cert, commit as `certs/sw-core01.crt`. Remove the old `crs309.mgmt.lab.gilman.io` cert.
6. **Verify the exact contract tofu will use**: `curl --cacert certs/sw-core01.crt -u "svc-tofu:…" https://10.10.10.2/rest/system/resource` → 200. Gate that proves transport, TLS pinning (self-signed-as-root + SAN-IP questions), and account policy in one call.
7. **Enable SSH** (`/ip service set ssh disabled=no address=10.10.10.0/24,192.168.1.0/24`) for the snapshot path; confirm serial-console availability physically.
8. Proceed to P2 (`just init`, adoption).

## 9. Docs and decisions updates (meta repo, companion changes)

| Doc | Change |
| --- | --- |
| `reference/networking/address-plan.md` | **D1**: `sw-core01 10.10.10.2` changes from "DHCP reservation" to "Static interface address"; drop the dead reservation from the gw01 template. *(Needs user sign-off — narrows a stated v2 design goal; same treatment would apply to `sw-mgmt01` 10.10.70.2.)* |
| `designs/lab-v2-core-network.md` | Name the authoritative `sw-core01` source — OpenTofu root `routeros/sw-core01` in `GilmanLab/networking` — parallel to the gw01 paragraph, incl. operator-apply + offline-CI posture. |
| `runbooks/` | New `sw-core01-configuration.md`: bootstrap, snapshot procedure, plan/apply flow, cutover record, recovery, purge/adopt rule, drift-check cadence. |
| `decisions/` | New **ADR-0004: Manage RouterOS devices with OpenTofu** — drivers, consequences (no commit-confirmed → adopt-only mgmt path + snapshot discipline; CI cannot plan), scope (sw-core01 now; rtr01/CCR2004 later). |
| `reference/networking/naming.md` | No change — `sw-core01` already registered. |

## 10. Open questions for the user

1. **D1 static-vs-reservation** — needs an explicit call since it amends a design-doc goal.
2. **`ether1` role**: disabled dead port (proposed default), or untagged VLAN-10 emergency access port? Emergency access is also an unmonitored L2 door into the mgmt VLAN.
3. **Winbox service**: keep restricted to 10.10.10.0/24, or disable and rely on webfig/SSH?
4. **NTP**: configure `10.10.10.1`/public NTP now as a tactical fix, or wait for a time-ownership decision? (Real clock drift observed in the log.)
5. **Tailscale operator path**: should `www-ssl`/`ssh` allowed-from include the source tailnet-routed traffic presents (depends on gw01 subnet-route SNAT)? Needs a one-off empirical check.

## 11. Flagged ungrounded claims

- Go-TLS acceptance of a pinned self-signed leaf and RouterOS SAN-IP emission (§3) — verified empirically at bootstrap step 6; fallback documented.
- Saved-plan-file internals for env-resolved provider config (§4) — [INFERENCE]; chosen path minimizes exposure under either interpretation.
- CRS309-1G-8S+ serial console presence — physical check required before P4.
- Exact current-latest routeros provider version — pin `~> 1.0` with committed lock file; resolve at `tofu init`.
- Whether deleting the defconf bridge implicitly removes its port rows, and whether `routeros_ip_dns` needs an import — both surfaced by the P2 adoption plan before anything mutates.
