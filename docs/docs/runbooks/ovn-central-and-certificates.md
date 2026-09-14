---
title: Operate OVN central and certificates
description: Issue and renew OVN certificates, deploy the durable central VM and chassis configuration, and recover the control plane from ENOSPC and TLS trust failures.
---

# Operate OVN central and certificates

Use this runbook to issue or renew OVN certificates, deploy or rebuild
`ovncentral01`, converge the four IncusOS chassis, and recover after an OVN
control-plane outage. The [network address and VLAN
plan](../reference/networking/address-plan.md#ovn-external-addresses) is the
only source for central endpoints, the provider uplink, and external address
allocations.

The durable central is an OpenTofu-owned VM pinned to `nas01`'s unmanaged
`mgmt` bridge. It runs `ovn-northd` and standalone northbound and southbound
databases. Both databases accept mutual TLS only. Fleet owns the VM, the
central service lifecycle, Incus client TLS, all four chassis, and the
physical uplink.

Fleet is the source of truth for these procedures. The recovery implementation
is fleet commit
[`b82fa1d`](https://github.com/GilmanLab/fleet/commit/b82fa1d), proposed in
[fleet PR #20](https://github.com/GilmanLab/fleet/pull/20). Its canonical
files are
[`config.py`](https://github.com/GilmanLab/fleet/blob/b82fa1d/cluster/src/fleet_cluster/config.py),
the [`central` deploy](https://github.com/GilmanLab/fleet/blob/b82fa1d/cluster/src/fleet_cluster/deploys/ovn_central.py),
the [`ovn-trust-roll` deploy](https://github.com/GilmanLab/fleet/blob/b82fa1d/cluster/src/fleet_cluster/deploys/ovn_trust_roll.py),
and the [`fleet-cluster` CLI](https://github.com/GilmanLab/fleet/blob/b82fa1d/cluster/src/fleet_cluster/cli.py).
Use one reviewed fleet revision for every command in a procedure.

## Preconditions and required access

- Trusted administration workstation with `openssl`, `ovn-nbctl`, `sops`,
  `jq`, OpenTofu, `just`, Moon, and the fleet-pinned Python environment.
- `GilmanLab/fleet` and `GilmanLab/secrets` checkouts. Use the reviewed revision
  of each repository.
- `lab-admin` AWS credentials for the SOPS KMS key and the OpenTofu state
  backend. Set `GLAB_AWS_STATE_BUCKET` to the existing fleet state bucket.
- An authenticated `nas01` Incus remote. Set `INCUS_CONF` to the existing
  administrator configuration so OpenTofu uses the pinned cluster certificate
  and client identity; do not enable automatic certificate acceptance.
- An owner-only absolute directory for plaintext ceremony material. Keep it
  outside every repository, set mode `0700`, and remove it after deployment.
- Before a planned IncusOS member reboot, create the persistent receipt
  directory on the execution host. It must already exist, be writable by its
  owner, and have mode `0700`; `fleet-cluster reboot` refuses the request
  before contacting the API when the directory is absent.
- A maintenance window for TLS rotation or central replacement. TLS rotation
  creates a bounded control-plane outage without replacing the VM. A central
  replacement is reserved for bootstrap or package changes and has the
  database consequences described below.

## Safety impact

- The OVN CA is an application-scoped offline CA: EC P-256, ten-year validity,
  `CA:TRUE`, and no path-length constraint. It is not the ADR-0005 KMS-root
  hierarchy. Here, offline means that no CA signing service or CA private key
  is deployed. A controlled issuance ceremony may use a connected
  administration workstation because KMS-backed SOPS escrow can require
  connectivity. Revisit Vault-backed issuance only when Vault PKI exists and
  there is a reason to migrate.
- Central and each chassis have separate two-year leaves. The Incus daemon
  uses the `nas01` leaf as its global OVN client identity; rotating `nas01`
  changes both that identity and the `nas01` chassis identity in one converge.
- Never deliver the CA private key to a node. Never put a leaf private key in
  OpenTofu variables, state, cloud-init, an IncusOS seed, a command argument,
  or a log.
- `fleet-cluster central-tls` is the only central TLS delivery path. It
  validates the complete CA, certificate, and key set, installs changed files
  only, refuses a change while any central component is active, and never
  starts, stops, or restarts a component. It does not touch `/var/lib/ovn`.
- Do not restart central as a repair. A restart disconnects every chassis and
  Incus client at once but does not repair the cause. Planned service work is
  an explicit `stopped` transition followed by `running`.
- Replacing `ovncentral01` starts the standalone databases empty unless a
  reviewed, compatible database backup is restored. Automatic reconstruction
  of existing sandbox network state has not been qualified. Without a backup,
  treat existing sandbox networking as invalid and recreate the disposable
  sandboxes through the normal lifecycle after central is healthy. This is not
  a durability promise for long-lived workloads.
- The retired `sandbox01` spike central is not a rollback target. Do not
  reinstall or restart it.
- Treat log truncation as destructive recovery. Capture evidence outside the
  central VM, archive it, record its SHA-256 digest, and obtain approval that
  names each file before truncating anything. Never truncate an OVN database or
  any path under `/var/lib/ovn`.
- `ovn-trust-roll` restarts only `incus.service` on explicitly selected
  members. It briefly interrupts that member's API, in-flight operations, and
  `incus exec` sessions. Run it without `--confirm` first, then obtain approval
  for the named members. It does not write a persistent trust marker.

## Issue the initial certificate set

Run the controlled issuance ceremony from fleet's `cluster/` directory:

```sh
export OVN_TLS_DIR=/absolute/path/to/owner-only-directory
install -d -m 0700 "$OVN_TLS_DIR"

cd /path/to/fleet/cluster
uv run --locked python -m fleet_cluster ovn-ceremony \
  --dir "$OVN_TLS_DIR" \
  --mint-ca
```

The command creates `ca.crt` and `ca.key`, the `ovncentral01` certificate and
key, and one certificate and key for each chassis. It prints JSON containing
subjects, expiry dates, SHA-256 fingerprints, and the required SOPS escrow
path for every artifact. It never prints a private key or contacts the
cluster.

`--mint-ca` is required because this procedure establishes the initial trust
domain. In every later ceremony, materialize the existing CA first. Without
`--mint-ca`, an absent CA is a refusal rather than an implicit replacement.

Record the reported fingerprint and update the pinned
`OVN_CA_FINGERPRINT_SHA256` in fleet's canonical `config.py` through a reviewed
commit before deployment. Delivery refuses a CA that does not match the pin.

Review the JSON and escrow every certificate/key pair at the paths it reports:

- CA: `fleet/shared/ovn-ca.sops.yaml`
- central leaf: `fleet/shared/ovn-central.sops.yaml`
- chassis leaves: `fleet/<member>/ovn.sops.yaml`

Use the secrets repository's normal SOPS and review flow. KMS-backed SOPS
escrow can require network access; the offline issuer model does not require
physical workstation disconnection. Each OVN file has `certificate` and `key`
fields. Do not deploy until all six identities can be materialized back into
one mode-`0700` directory with private keys mode `0600`. After escrow, remove
the plaintext CA key before starting deployment:

```sh
rm -f -- "$OVN_TLS_DIR/ca.key"
```

The cluster converge needs `ca.crt` and the four chassis pairs; central
deployment also needs the central pair.

### Materialize the escrowed set

Create a fresh owner-only directory, then decrypt the public CA certificate,
the central pair, and all four chassis pairs from the reviewed secrets
checkout:

```sh
export OVN_TLS_DIR=/absolute/path/to/owner-only-directory
install -d -m 0700 "$OVN_TLS_DIR"
cd /path/to/secrets

AWS_PROFILE=lab-admin sops -d --extract '["certificate"]' \
  fleet/shared/ovn-ca.sops.yaml >"$OVN_TLS_DIR/ca.crt"
AWS_PROFILE=lab-admin sops -d --extract '["certificate"]' \
  fleet/shared/ovn-central.sops.yaml >"$OVN_TLS_DIR/ovncentral01.crt"
AWS_PROFILE=lab-admin sops -d --extract '["key"]' \
  fleet/shared/ovn-central.sops.yaml >"$OVN_TLS_DIR/ovncentral01.key"

for member in nas01 lab01 lab02 lab03; do
  AWS_PROFILE=lab-admin sops -d --extract '["certificate"]' \
    "fleet/$member/ovn.sops.yaml" >"$OVN_TLS_DIR/$member.crt"
  AWS_PROFILE=lab-admin sops -d --extract '["key"]' \
    "fleet/$member/ovn.sops.yaml" >"$OVN_TLS_DIR/$member.key"
done

chmod 0644 "$OVN_TLS_DIR"/*.crt
chmod 0600 "$OVN_TLS_DIR"/*.key
```

For a controlled leaf-issuance ceremony only, also materialize the CA key:

```sh
AWS_PROFILE=lab-admin sops -d --extract '["key"]' \
  fleet/shared/ovn-ca.sops.yaml >"$OVN_TLS_DIR/ca.key"
chmod 0600 "$OVN_TLS_DIR/ca.key"
```

Remove `ca.key` again after the new leaf pair is escrowed and before
deployment.

## Deploy the durable central and chassis

### 1. Plan and apply the central VM

Point OpenTofu at the public CA and central certificates. The private central
key is deliberately not an input:

```sh
cd /path/to/fleet/incus/ovn-central
export AWS_PROFILE=lab-admin
export GLAB_AWS_STATE_BUCKET=<existing-fleet-state-bucket>
export INCUS_CONF=<existing-administrator-incus-config>
export TF_VAR_ovn_ca_certificate_file="$OVN_TLS_DIR/ca.crt"
export TF_VAR_central_certificate_file="$OVN_TLS_DIR/ovncentral01.crt"

just init
just plan
tofu show tfplan
just apply
```

Review the saved plan before `just apply`. The root owns only `ovncentral01`.
It must not change chassis configuration or the provider uplink. The VM's TLS
gates keep the database components stopped until all three central TLS files
exist.

### 2. Deliver central TLS and start the components

Wait for the Incus guest agent and cloud-init before delivering TLS material.
The agent check stops after 150 seconds; the in-guest cloud-init wait stops after
10 minutes:

```sh
(
  set -eu
  for attempt in $(seq 1 30); do
    if incus exec --project default nas01:ovncentral01 -- true \
      >/dev/null 2>&1; then
      ovn_central_agent_ready=true
      break
    fi
    sleep 5
  done
  test "${ovn_central_agent_ready:-false}" = true || {
    echo "ovncentral01 guest agent did not become ready" >&2
    exit 1
  }
  incus exec --project default nas01:ovncentral01 -- \
    timeout 600 cloud-init status --wait
)
```

Stop if either check fails. From fleet's `cluster/` directory, validate and
review the TLS delivery plan before applying it. The directory must be an
absolute owner-only path and contain `ca.crt`, `ovncentral01.crt`, and
`ovncentral01.key`:

```sh
cd ../../cluster
uv run --locked python -m fleet_cluster central-tls \
  --dir "$OVN_TLS_DIR" \
  --dry-run
uv run --locked python -m fleet_cluster central-tls \
  --dir "$OVN_TLS_DIR"
uv run --locked python -m fleet_cluster central --state running
```

On the initial deployment, the TLS gates leave every central component
stopped. `central-tls` validates the certificate chain, validity periods,
central identity, matching key, directory mode `0700`, and key mode `0600`.
It stages and verifies changed files before installing them as `root:root`
with the CA and leaf mode `0644` and the key mode `0600`. No private key is an
OpenTofu input.

The lifecycle command starts the northbound database, southbound database,
`ovn-northd`, and the remote-listener publisher in dependency order. It
refuses to report success when the CA certificate, central certificate, or
central key is missing. A rerun with the requested state already present is a
no-op.

### 3. Verify central before touching a chassis

Print the root's read-only acceptance commands and run each command exactly as
rendered:

```sh
cd ../incus/ovn-central
tofu output -json acceptance_commands | jq -r '.[]'
```

Require these observations:

- Each database reports exactly one `pssl:` connection from
  `get-connection`.
- The database sockets match the TLS endpoints in the address plan; no `ptcp:`
  connection exists.
- The central and remote-listener services are active.

From the trusted workstation, verify a real client connection with the
`nas01` identity. Copy the northbound endpoint from the address plan rather
than recording it in this runbook:

```sh
export OVN_NB_ENDPOINT='ssl:<northbound-endpoint-from-address-plan>'
ovn-nbctl --db="$OVN_NB_ENDPOINT" \
  --private-key="$OVN_TLS_DIR/nas01.key" \
  --certificate="$OVN_TLS_DIR/nas01.crt" \
  --ca-cert="$OVN_TLS_DIR/ca.crt" \
  show
```

The command must return northbound state without a trust prompt. Repeat with a
`tcp:` endpoint only as a negative, read-only probe and require refusal; do not
weaken the server configuration to make that probe connect.

### 4. Converge Incus and all four chassis

Run the read-only provider-parent preflight first, then the complete OVN
converge:

```sh
cd /path/to/fleet/cluster
moon run fleet-cluster:ovn-preflight

GLAB_SECRETS_DIR=/path/to/secrets \
FLEET_OVN_TLS_DIR="$OVN_TLS_DIR" \
  moon run fleet-cluster:ovn
```

`fleet-cluster ovn` validates the complete certificate set before planning any
change. It sets the Incus client TLS trio and northbound connection before it
updates a chassis, then converges each chassis and the physical uplink. It
never disables a chassis, clears the northbound connection, changes IncusOS
system network configuration, or reboots a member.

If this procedure minted a new CA, complete the
[explicit four-member trust roll](#recycle-incus-daemons-after-client-trust-changes)
after this converge and before the no-op and connectivity checks. Initial
delivery does not exempt running Incus daemons from rebuilding their in-memory
clients.

Run the same command again and require a no-op. Repeat the northbound TLS check
and the OpenTofu acceptance commands. Full sandbox lifecycle acceptance is a
separate agentcompute qualification; central and chassis checks do not prove
it.

Remove the plaintext directory after the escrow revision and deployment
evidence are reviewed:

```sh
rm -rf -- "$OVN_TLS_DIR"
unset OVN_TLS_DIR TF_VAR_ovn_ca_certificate_file TF_VAR_central_certificate_file
```

## Converge central log-exhaustion controls

The `central` command owns the central VM's logging configuration. Committed
source is not activation evidence: run the command against the target VM and
record its result.

```sh
cd /path/to/fleet/cluster
uv run --locked python -m fleet_cluster central --state running
```

The command converges these controls:

- The two `ovsdb-server` processes log at `syslog:warn` and `file:info`.
  `ovn-northd` retains its stricter packaged `syslog:err` setting.
- `/var/log/ovn/*.log` uses a `64MiB` rotation threshold, six retained
  archives, and a five-minute logrotate check. A file can exceed `64MiB`
  between checks, and compressed size depends on content. This is a retention
  policy, not a hard byte cap or a fixed-size compressed quota.
- The persistent journal has `SystemMaxUse=512M`. Fleet also manages its file,
  free-space, runtime, and per-service rate limits.
- Fleet manages `/etc/rsyslog.conf` so the `imuxsock` input rate-limits
  messages at severity `4` through a 30-second interval with a burst of `500`.
  The existing `/etc/rsyslog.d/*.conf` local and forwarding rules remain
  included.

When a managed logging file changes, the command reloads systemd and restarts
only `rsyslog` and/or `systemd-journald` as required. It does not restart an OVN
service. It applies live `ovsdb-server` vlog levels through `appctl`; a helper
failure fails an explicit converge. The unit drop-ins deliberately use
`ExecStartPost=-`, so a future helper failure cannot prevent a database from
starting.

The running-state converge also refuses a missing or inactive
`logrotate.timer`, a root filesystem that does not match the provisioned disk,
less than `1GiB` of free root space, or incomplete central TLS material. Verify
the active state and rendered values:

```sh
incus exec --project default nas01:ovncentral01 -- \
  rsyslogd -N1
incus exec --project default nas01:ovncentral01 -- \
  logrotate --debug /etc/logrotate.d/ovn-common
incus exec --project default nas01:ovncentral01 -- \
  systemctl is-active rsyslog systemd-journald logrotate.timer
incus exec --project default nas01:ovncentral01 -- \
  systemctl list-timers logrotate.timer --no-pager
incus exec --project default nas01:ovncentral01 -- \
  cat /etc/rsyslog.conf /etc/logrotate.d/ovn-common \
      /etc/systemd/system/logrotate.timer.d/10-ovn-central-cadence.conf
incus exec --project default nas01:ovncentral01 -- \
  systemd-analyze cat-config systemd/journald.conf
for ctl in /run/ovn/ovnnb_db.ctl /run/ovn/ovnsb_db.ctl; do
  incus exec --project default nas01:ovncentral01 -- \
    ovn-appctl -T 2 -t "$ctl" vlog/list
done
```

Require a valid rsyslog configuration, active logging services and timer, the
five-minute timer override, the source-managed values above, and `WARN` in the
syslog column plus `INFO` in the file column for every module in both
`ovsdb-server` tables. On a second `central --state running` converge, require
every rendered file to be unchanged and no logging daemon restart. The
idempotent northd enable probe and vlog no-drift command can still appear as
pyinfra operations; do not require a zero-operation report.

The approved 2026-09-14 converge activated these controls. Both logging daemons
were active with fresh start timestamps; `rsyslogd` 8.2512.0 validation and
the logrotate debug pass succeeded. `logrotate.timer` last ran at 16:21 UTC
and was next scheduled for 16:25 UTC. Every module in both database vlog
tables reported syslog `WARN` and file `INFO`. The northbound, southbound, and
`ovn-northd` PIDs and `ActiveEnterTimestampMonotonic` values still matched the
pre-recovery baseline, so activation did not restart an OVN process.

## Renew a chassis leaf

Renewing a leaf under the same CA does not revoke its old certificate. This
deployment does not configure per-leaf revocation. If a leaf private key is
exposed, use the complete CA and all-five-leaf replacement below; a leaf-only
renewal is not containment.

Use "Materialize the escrowed set," including the CA key, to create a fresh
owner-only directory. Rotation must use the existing CA; the ceremony refuses
to mint a replacement CA during `--rotate`.

Issue exactly the named chassis leaf:

```sh
export OVN_TLS_DIR=/absolute/path/to/owner-only-directory
cd /path/to/fleet/cluster
uv run --locked python -m fleet_cluster ovn-ceremony \
  --dir "$OVN_TLS_DIR" \
  --leaf lab03 \
  --rotate
```

Replace `lab03` with the intended member. Compare the reported CA fingerprint
with the escrowed CA, verify that only the named leaf reports `reissued`, and
escrow the new certificate/key pair. Remove the plaintext CA key after escrow
and before deployment:

```sh
rm -f -- "$OVN_TLS_DIR/ca.key"
```

Run the converge from fleet's `cluster/` directory:

```sh
GLAB_SECRETS_DIR=/path/to/secrets \
FLEET_OVN_TLS_DIR="$OVN_TLS_DIR" \
  moon run fleet-cluster:ovn
```

Only the named chassis should change unless the named member is `nas01`.
Rotating `nas01` also changes the cluster-wide Incus OVN client certificate and
key. In that case, follow the
[explicit four-member trust roll](#recycle-incus-daemons-after-client-trust-changes)
so every Incus daemon uses the new client identity. For another member, no
Incus daemon roll is required. Require northbound connectivity, verify all four
chassis remain configured, and rerun the deploy to a no-op before removing the
plaintext directory.

## Rotate the central leaf or complete OVN trust set

TLS-only renewal does not replace `ovncentral01`. The owner approved both a
central-leaf renewal under the current CA and a complete replacement of the CA
and all five leaves. Both use `central-tls` while the central components are
stopped, preserve `/var/lib/ovn`, and leave the northbound and southbound
databases in place.

### Prepare and escrow the new material

For central-leaf renewal, use "Materialize the escrowed set," including the
current CA key, and rotate only the central leaf:

```sh
export OVN_TLS_DIR=/absolute/path/to/owner-only-directory
cd /path/to/fleet/cluster
uv run --locked python -m fleet_cluster ovn-ceremony \
  --dir "$OVN_TLS_DIR" \
  --leaf central \
  --rotate
```

Compare the reported CA fingerprint with escrow, confirm only the central leaf
reports `reissued`, and escrow the new central certificate/key pair.

For a complete CA replacement, use a fresh empty owner-only directory. This is
the only later ceremony that may use `--mint-ca`; do not use `--rotate` or a
leaf selector:

```sh
export OVN_TLS_DIR=/absolute/path/to/new-owner-only-directory
install -d -m 0700 "$OVN_TLS_DIR"
cd /path/to/fleet/cluster
uv run --locked python -m fleet_cluster ovn-ceremony \
  --dir "$OVN_TLS_DIR" \
  --mint-ca
```

Review and escrow the new CA, central pair, and four chassis pairs. Confirm all
six identities can be materialized from the reviewed secrets checkout. Record
the reported CA fingerprint. Before delivery, update the pinned
`OVN_CA_FINGERPRINT_SHA256` in fleet's canonical
[`config.py`](https://github.com/GilmanLab/fleet/blob/b82fa1d/cluster/src/fleet_cluster/config.py)
through a reviewed commit. Every delivery path refuses a CA that does not match
that pin.

In either procedure, remove the plaintext CA key after escrow and before
deployment:

```sh
rm -f -- "$OVN_TLS_DIR/ca.key"
```

Keep the prior deployment set in a separate owner-only directory through
verification so the old client identity can be tested for rejection. The new
deployment directory must contain `ca.crt`, `ovncentral01.crt`,
`ovncentral01.key`, and each member's certificate/key pair.

### Review and apply the rotation

Before the outage, record the current NB_Global, SB_Global, and representative
logical-switch UUIDs. Validate the central delivery while the service is still
running:

```sh
cd /path/to/fleet/cluster
uv run --locked python -m fleet_cluster central-tls \
  --dir "$OVN_TLS_DIR" \
  --dry-run
```

The dry run writes nothing. For a central-leaf renewal it should report the
central certificate and key as changed and the CA as unchanged. For a complete
CA replacement it should report all three central TLS files as changed and
note that applying them while components are active would be refused.

Apply the bounded outage in this order:

```sh
uv run --locked python -m fleet_cluster central --state stopped
uv run --locked python -m fleet_cluster central-tls \
  --dir "$OVN_TLS_DIR"
uv run --locked python -m fleet_cluster central --state running
GLAB_SECRETS_DIR=/path/to/secrets \
FLEET_OVN_TLS_DIR="$OVN_TLS_DIR" \
  moon run fleet-cluster:ovn
```

#### Recycle Incus daemons after client trust changes

When the cluster-wide Incus OVN CA, client certificate, or client key changes,
plan the required daemon roll with explicit member selectors. This includes a
new CA and renewal of the `nas01` leaf:

```sh
uv run --locked python -m fleet_cluster ovn-trust-roll \
  --member lab01 \
  --member lab02 \
  --member lab03 \
  --member nas01
```

Review the CA fingerprint, selected members, and pre-restart `server_pid`
values. After separate approval for those four daemon restarts, repeat the
same command with `--confirm`:

```sh
uv run --locked python -m fleet_cluster ovn-trust-roll \
  --member lab01 \
  --member lab02 \
  --member lab03 \
  --member nas01 \
  --confirm
```

The command enforces `lab01`, `lab02`, `lab03`, then `nas01` order regardless
of selector order. It waits until each selected member answers with a different
`server_pid` before touching the next member; `nas01`, the command's remote and
central VM host, remains last. It restarts no instance, chassis, central
process, or member operating system.

Do not run the chassis/client converge while northbound is stopped: Incus must
reach northbound to update its global client TLS configuration. During a
complete CA replacement, starting central before that converge creates a brief
fail-closed trust mismatch. Do not add a dual-CA interval. The fleet deploy
updates the stored Incus client identity and all four chassis; the explicit
trust roll then makes each selected Incus daemon rebuild its in-memory clients.
A central-leaf renewal under the same CA does not require this trust roll.

Repeat the central acceptance commands, the northbound TLS check, and the
chassis checks. Require the recorded NB_Global, SB_Global, and logical-switch
UUIDs to be unchanged. For a complete CA replacement, require a new chassis
identity to authenticate to both database endpoints and the matching old
identity to be rejected by both. Verify a cross-member guest path after the
rotation, including a guest restart, then rerun `central-tls --dry-run` and the
fleet deploy to no-ops.

The 2026-09-14 complete-set rotation replaced the central's three TLS files,
the stored Incus global client identity, and all four chassis identities. It
preserved NB_Global, SB_Global, and two logical-switch UUIDs. The certificate
and guest-path checks passed, but they did not prove that every Incus daemon
had rebuilt its in-memory OVN clients. Three daemons retained the prior CA and
later caused the ENOSPC incident below. A complete-set rotation is not complete
until the explicit PID-witnessed trust roll and passive-open check pass.

### Update OpenTofu public metadata

Keep OpenTofu's public cloud-init metadata aligned with the active CA and
central certificate so a later deliberate VM replacement starts from the
current public trust set. The central private key remains outside OpenTofu:

```sh
cd /path/to/fleet/incus/ovn-central
export AWS_PROFILE=lab-admin
export GLAB_AWS_STATE_BUCKET=<existing-fleet-state-bucket>
export INCUS_CONF=<existing-administrator-incus-config>
export TF_VAR_ovn_ca_certificate_file="$OVN_TLS_DIR/ca.crt"
export TF_VAR_central_certificate_file="$OVN_TLS_DIR/ovncentral01.crt"
just plan
tofu show tfplan
just apply
```

Apply only an in-place public metadata update. Stop if the plan replaces the VM
or includes any private key. Remove the materialized deployment directories
after this update and all rotation checks pass.

## Rebuild central

Use deliberate VM replacement for bootstrap or package changes, not for TLS
renewal. Replacing the VM starts the standalone databases empty unless a
reviewed, compatible database backup is restored. Before replacement, decide
whether to restore such a backup through its established recovery procedure.
Without one, plan to recreate all disposable sandboxes through the normal
lifecycle.

For a planned replacement, stop a reachable central through fleet:

```sh
cd /path/to/fleet/cluster
uv run --locked python -m fleet_cluster central --state stopped
```

During recovery, attempt the same transition only when the VM answers through
Incus. If the VM is absent or cannot execute commands, record that failure and
continue with deliberate replacement; do not add another access path.

Plan and apply the replacement using public TLS material only:

```sh
cd /path/to/fleet/incus/ovn-central
export AWS_PROFILE=lab-admin
export GLAB_AWS_STATE_BUCKET=<existing-fleet-state-bucket>
export INCUS_CONF=<existing-administrator-incus-config>
export TF_VAR_ovn_ca_certificate_file="$OVN_TLS_DIR/ca.crt"
export TF_VAR_central_certificate_file="$OVN_TLS_DIR/ovncentral01.crt"
tofu plan -replace=incus_instance.central -out=tfplan
tofu show tfplan
just apply
```

After apply, wait for the guest agent and cloud-init as in the initial
deployment. Restore a reviewed database backup, when available, before
starting central. Then deliver the complete active TLS set and converge in
order:

```sh
cd ../../cluster
uv run --locked python -m fleet_cluster central-tls \
  --dir "$OVN_TLS_DIR" \
  --dry-run
uv run --locked python -m fleet_cluster central-tls \
  --dir "$OVN_TLS_DIR"
uv run --locked python -m fleet_cluster central --state running
GLAB_SECRETS_DIR=/path/to/secrets \
FLEET_OVN_TLS_DIR="$OVN_TLS_DIR" \
  moon run fleet-cluster:ovn
```

Run all central acceptance commands and the northbound TLS check. If a reviewed
database backup was restored, validate it through its recovery procedure.
Otherwise, the rebuilt databases remain empty. Automatic reconstruction by
Incus has not been qualified. Treat every pre-rebuild sandbox network as
invalid and delete and recreate its disposable sandbox through the normal
lifecycle. Do not restore an unreviewed database copy.

## Qualify a member reboot during a central outage

This is a planned acceptance procedure, not routine outage repair. Create and
verify the persistent receipt directory **before** stopping central. On the
administration Mac, use:

```sh
RECEIPT_DIR="$HOME/Library/Application Support/GilmanLab/fleet/reboot-receipts"
install -d -m 0700 "$RECEIPT_DIR"
test -d "$RECEIPT_DIR" && test -w "$RECEIPT_DIR"
test "$(stat -f '%Su' "$RECEIPT_DIR")" = "$USER"
test "$(stat -f '%Lp' "$RECEIPT_DIR")" = 700
```

Choose a new stable request ID for each intended reboot. After recording
management and guest-path baselines, stop central and submit exactly one
confirmed reboot:

```sh
cd /path/to/fleet/cluster
REQUEST_ID="ovn-central-outage-$(date -u +%Y%m%dT%H%M%SZ)"
uv run --locked python -m fleet_cluster central --state stopped
uv run --locked python -m fleet_cluster reboot \
  --member lab03 \
  --request-id "$REQUEST_ID" \
  --receipt-dir "$RECEIPT_DIR" \
  --confirm
```

The receipt proves that fleet accepted the request; it does not prove that the
member rebooted or returned healthy. Require the member management API to
return and the cluster to report the member `Online` and `Fully operational`
while central remains stopped. Measure a guest path that does not use the
rebooted member and one that does. Then start central exactly once:

```sh
uv run --locked python -m fleet_cluster central --state running
```

Do not restart central, a chassis, OVS, or the uplink. Require both guest paths
to recover naturally, allow a later reaper scan to clear outage residue, and
rerun the fleet deploy to a no-op. Reusing the same request ID must not submit
another reboot.

The Phase 5 qualification used request
`phase5-central-outage-lab03-01` and the persistent directory
`/Users/josh/Library/Application Support/GilmanLab/fleet/reboot-receipts`.
The first invocation was refused before an API call because that directory did
not exist. After it was created with mode `0700`, the same request ID was
accepted once. The management
API returned after approximately 112 seconds while central was still stopped.
A surviving path completed three of three pings throughout; the rebooted
guest completed zero of three during the outage and three of three after the
single central start.

## Recover ENOSPC caused by stale in-memory OVN trust

Use this procedure when the central root is full and the logs show a high-rate
TLS reject/reconnect loop even though the installed CA and leaf certificates
validate. Incus constructs its northbound and southbound TLS clients when
`incus.service` starts. Updating `network.ovn.*` does not replace those
in-memory clients.

### 1. Capture and archive evidence

Work from an owner-only directory outside every repository. The commands below
are read-only against the central VM:

```sh
export CENTRAL=nas01:ovncentral01
export EVIDENCE_DIR=/absolute/owner-only/path/ovn-enospc-$(date -u +%Y%m%dT%H%M%SZ)
install -d -m 0700 "$EVIDENCE_DIR"

incus config show --project default "$CENTRAL" --expanded \
  >"$EVIDENCE_DIR/incus-expanded-before.yaml"
incus cluster list nas01: >"$EVIDENCE_DIR/cluster-before.txt"
incus exec --project default "$CENTRAL" -- \
  systemctl show \
    -p Id -p ActiveEnterTimestampMonotonic -p MainPID \
    ovn-ovsdb-server-nb.service \
    ovn-ovsdb-server-sb.service \
    ovn-northd.service \
  >"$EVIDENCE_DIR/central-units-before-recovery.txt"
incus exec --project default "$CENTRAL" -- sh -c \
  'df -h / /var/log; findmnt /; blockdev --getsize64 /dev/sda' \
  >"$EVIDENCE_DIR/root-before.txt"
```

Record metadata for only the exhausted files:

```sh
incus exec --project default "$CENTRAL" -- python3 -c '
import json
import os
import sys
import time

fields = ("dev", "ino", "mode", "uid", "gid", "size", "blocks", "mtime_ns", "ctime_ns")
files = []
for path in sys.argv[1:]:
    value = os.stat(path)
    files.append({"path": path, **{f"st_{field}": getattr(value, f"st_{field}") for field in fields}})
print(json.dumps({"captured_at": time.time(), "files": files}, indent=2))
' \
  /var/log/syslog \
  /var/log/ovn/ovsdb-server-nb.log \
  /var/log/ovn/ovsdb-server-sb.log \
  >"$EVIDENCE_DIR/stat-before.json"
```

Capture the first and last `20MiB` of each file onto the execution host. Do not
store these segments inside the VM whose root is full:

```sh
for path in \
  /var/log/syslog \
  /var/log/ovn/ovsdb-server-nb.log \
  /var/log/ovn/ovsdb-server-sb.log
do
  name=${path##*/}
  incus exec --project default "$CENTRAL" -- head -c 20971520 "$path" \
    >"$EVIDENCE_DIR/$name.first-20MiB.log"
  incus exec --project default "$CENTRAL" -- tail -c 20971520 "$path" \
    >"$EVIDENCE_DIR/$name.last-20MiB.log"
done
```

Inspect certificate subjects, issuers, validity, SANs, and fingerprints without
reading private keys. Compare the installed central CA and leaf, the Incus
global `network.ovn.*` material, the four chassis identities, CA creation time,
and each Incus daemon's start evidence. A valid installed set does not exclude
stale in-memory trust. Identify the source members that continue the reconnect
loop; do not select a member that has already rebuilt its clients.

If the VM remains responsive, complete a full-file signature scan before
truncation rather than extrapolating only from the captured windows. Save the
scanner, its stderr, and its machine-readable results in the evidence
directory. Then freeze the pre-recovery record:

```sh
tar -C "$(dirname "$EVIDENCE_DIR")" -czf "$EVIDENCE_DIR.tar.gz" \
  "$(basename "$EVIDENCE_DIR")"
shasum -a 256 "$EVIDENCE_DIR.tar.gz" | tee "$EVIDENCE_DIR.tar.gz.sha256"
```

Stop here. Obtain approval that names the exact files to truncate and the
members whose `incus.service` may be restarted. Do not modify the archive after
approval; write recovery results into the directory beside it.

### 2. Reclaim log space

After approval, truncate only the three captured log files in place. In-place
truncation preserves the inode held by each running logger:

Immediately before truncation, compare each path's device and inode with
`stat-before.json`. If rotation replaced a file, capture the replacement and
renew approval rather than truncating a file that is absent from the archive.

```sh
incus exec --project default "$CENTRAL" -- truncate -s 0 -- \
  /var/log/syslog \
  /var/log/ovn/ovsdb-server-nb.log \
  /var/log/ovn/ovsdb-server-sb.log
incus exec --project default "$CENTRAL" -- df -h / /var/log \
  | tee "$EVIDENCE_DIR/df-after-truncate.txt"
```

Do not stop or restart central, reboot the guest, grow the disk, rotate TLS
again, or weaken TLS. If the guest filesystem is smaller than the provisioned
root device, stop and repair that separate growth fault. A root that already
matches its provisioned disk needs bounded logging and removal of the loop, not
an ad hoc size increase.

### 3. Roll only the stale Incus daemons

Use explicit selectors derived from the evidence. This example is the approved
Phase 5 selection; `lab03` is deliberately absent because its Incus daemon had
already restarted after the CA changed:

```sh
cd /path/to/fleet/cluster
uv run --locked python -m fleet_cluster ovn-trust-roll \
  --member lab01 \
  --member lab02 \
  --member nas01
```

Review the plan and its pre-restart `server_pid` values. After approval, repeat
the exact selection with `--confirm`:

```sh
uv run --locked python -m fleet_cluster ovn-trust-roll \
  --member lab01 \
  --member lab02 \
  --member nas01 \
  --confirm
```

The command first requires central root headroom. It then restarts one selected
`incus.service` at a time and proves that member is serving with a different
PID before continuing. If one member does not return, the command abandons the
rest of the roll.

### 4. Verify recovery

Require every member to report `Online`, and prove that no central process
restarted:

```sh
incus cluster list nas01: | tee "$EVIDENCE_DIR/cluster-after.txt"
incus exec --project default "$CENTRAL" -- \
  systemctl show \
    -p Id -p ActiveEnterTimestampMonotonic -p MainPID \
    ovn-ovsdb-server-nb.service \
    ovn-ovsdb-server-sb.service \
    ovn-northd.service \
  >"$EVIDENCE_DIR/central-units-after-recovery.txt"
cmp "$EVIDENCE_DIR/central-units-before-recovery.txt" \
  "$EVIDENCE_DIR/central-units-after-recovery.txt"
```

Measure inbound connection churn over ten seconds:

```sh
passive_opens() {
  incus exec --project default "$CENTRAL" -- python3 -c '
rows = [line.split() for line in open("/proc/net/snmp") if line.startswith("Tcp:")]
print(dict(zip(rows[0][1:], rows[1][1:]))["PassiveOpens"])
'
}
before=$(passive_opens)
sleep 10
after=$(passive_opens)
printf "PassiveOpens before=%s after=%s delta=%s over 10 seconds\n" \
  "$before" "$after" "$((after - before))" \
  | tee "$EVIDENCE_DIR/passive-opens-after-recovery.txt"
test "$after" -eq "$before"
```

Repeat the central acceptance commands and northbound TLS check. Require stable
NB and SB connections and no new bad-certificate/reconnect flood. Do not
restart a host, guest, chassis, or central process to make these checks pass.

### Phase 5 recovery evidence

The 2026-09-14 scan covered all `151785740` lines and `19307134976` bytes in
`/var/log/syslog`, `ovsdb-server-nb.log`, and `ovsdb-server-sb.log`. The first
and last `20MiB` of all three files were captured off the VM. The `20GiB` root
matched the provisioned disk; this was not a guest filesystem growth failure.

The installed CA and leaves were valid, but the CA had been silently re-minted.
The Incus daemons on `lab01`, `lab02`, and `nas01` retained the old CA in
memory. After explicit approval, the operator truncated exactly the three logs
above and used `ovn-trust-roll` to recycle only those three daemons. `lab03`
was not restarted. All members returned `Online`; the central database and
`ovn-northd` PIDs and start timestamps were unchanged. No host, guest, chassis,
or central process restarted. Passive opens fell from `1039` per second to
`0` per second across a ten-second observation.

The incident-only evidence directory is
`/tmp/agentcompute-ovn-enospc-20260914/`. Its canonical recovery record includes
`forensics-findings.md`, `top-signatures.jsonl`, `stat-before.json`,
`approved-member-roll.stderr`, `connections-after-recovery.json`, and
`log-controls-verification.json`.

The immutable pre-recovery archive is
`/tmp/agentcompute-ovn-enospc-20260914.tar.gz`, with SHA-256
`1900270c232538a07588ba0adcccecb9ccbb9b64da71c0ccd02798a21b759926`.
It contains only the evidence captured before recovery. Later recovery outputs
under `/tmp/agentcompute-ovn-enospc-20260914/`, including the approved member
roll and post-recovery results, are directory additions and are not part of
that archive.
These `/tmp` paths record this incident; they are not prerequisites for a later
recovery. Create the owner-only evidence path described in step 1 instead.

## Recover from control-plane unavailability

Existing installed dataplane flows may continue while central is down. Treat
all OVN creates, updates, and deletes as unavailable regardless of that
traffic. Diagnose with read-only commands first:

```sh
cd /path/to/fleet/incus/ovn-central
tofu output -json acceptance_commands | jq -r '.[]'
incus exec --project default nas01:ovncentral01 -- \
  journalctl --no-pager -u ovn-ovsdb-server-nb -u ovn-ovsdb-server-sb \
  -u ovn-northd -u ovn-central-remotes
```

If the VM and complete TLS trio exist, converge the running state:

```sh
cd ../../cluster
uv run --locked python -m fleet_cluster central --state running
```

Do not use a restart, disable a chassis, clear
`network.ovn.northbound_connection`, or recreate the uplink. If the lifecycle
command reports missing or mismatched TLS material, leave the components
stopped and use `central-tls --dry-run` followed by `central-tls` with the
complete active set. Start central only after that delivery succeeds. Use
deliberate VM replacement only when bootstrap or package state is inconsistent;
missing TLS files alone do not require replacement.

An outage-created `Errored` NAT-enabled network retains its external address.
An isolated `nat=false` network has no external address to retain. Explicit
`sandbox.delete` first records expiry; if cleanup fails, the project and
remaining resources stay discoverable. The reaper retries in dependency order
on later scans. After central recovers, allow a later scan to delete forwards
and peers, NIC references, instances and snapshots, sandbox images, profiles,
networks and their ACLs, then the project. Do not restart infrastructure to
force cleanup, and do not report capacity as released until the network is
gone.

A provider-parent conflict is a different failure. Fleet preflight names the
competing default-project network, profile NIC, or instance NIC and stops
before changing the uplink. Identify the owner and remove or migrate that
consumer through its owning workflow. The reaper owns sandbox resources only;
it cannot repair an infrastructure parent conflict.

## Escalation

Stop and investigate rather than broadening the procedure when:

- The CA key is missing, compromised, expired, or does not match `ca.crt`. A
  new CA is a coordinated trust-domain replacement for central, Incus, and all
  four chassis; leaf rotation is not sufficient.
- A central plan changes resources other than the intended VM, or a chassis
  converge proposes a reboot, a northbound clear, a chassis disable, or an
  unrelated network change.
- Mutual TLS fails after certificate fingerprints and SANs match the reviewed
  escrow. Do not add plaintext listeners as a diagnostic bypass.
- Owned sandbox resources remain after central is healthy and a later reaper
  scan. Capture the named resource and backend error before any manual delete.
- Recovery would require the retired `sandbox01` central or an unreviewed OVN
  database backup.
