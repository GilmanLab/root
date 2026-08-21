---
title: Manage the sw-core01 configuration
description: Bootstrap, plan, apply, verify, and recover the OpenTofu-managed RouterOS configuration on sw-core01.
---

# Manage the sw-core01 configuration

Use this runbook to bring `sw-core01` under OpenTofu management and to apply
later configuration changes. The authoritative root is
[`routeros/sw-core01/`](https://github.com/GilmanLab/networking/tree/master/routeros/sw-core01)
in `GilmanLab/networking`. The
[Lab v2 core network design](../designs/lab-v2-core-network.md) defines the
accepted behavior, and the
[network address and VLAN plan](../reference/networking/address-plan.md) is the
canonical source for addresses, VLANs, and port roles.

## Preconditions and required access

- Use a reviewed checkout of `GilmanLab/networking`. The commands below run
  from that checkout's root.
- Install the repository toolchain, including `just`, OpenTofu, SOPS, SSH, SCP,
  OpenSSL, and `curl`.
- Connect from `10.10.10.0/24`, `192.168.1.0/24`, or `100.64.0.0/10`.
  Both the `svc-tofu` account and the RouterOS management services accept those
  source networks.
- Set `GLAB_AWS_STATE_BUCKET` to the lab state bucket and set
  `GLAB_SECRETS_DIR` to an absolute path to a current `GilmanLab/secrets`
  checkout. Use `AWS_PROFILE=lab-admin` unless another approved profile has
  equivalent state and SOPS access.
- Authenticate the AWS profile before `just init`, `just plan`, or
  `just apply`.
- For routine plan and apply operations, confirm that the pinned CA certificate
  exists at `routeros/sw-core01/certs/sw-core01-ca.crt`. The one-time bootstrap
  creates this file; do not generate a substitute certificate in the
  repository.
- Confirm that no other operator is changing `sw-core01`.
- Retain the current `admin` break-glass credential and a tested WebFig or SSH
  session before a cutover. The presence of a usable serial console on the
  CRS309-1G-8S+ has not been verified and must not be assumed.

The `plan` and `apply` recipes decrypt `username` and `password` from
`$GLAB_SECRETS_DIR/network/sw-core01/terraform.sops.yaml` and expose them only
as `ROS_USERNAME` and `ROS_PASSWORD` to the provider process. Do not create
OpenTofu credential variables or commit decrypted credentials.

## Safety impact

RouterOS has no commit-confirmed transaction for REST changes. Safe Mode covers
changes made in its terminal session; it does not cover changes made by an
OpenTofu apply through REST.

The management path is adopt-only. A cutover or later apply must not replace or
recreate any of these resources:

- `bridge-lab`;
- the `sfp-sfpplus8` bridge-port row;
- the VLAN 10 bridge-VLAN row;
- `mgmt-vlan10`;
- `10.10.10.2/24` on `mgmt-vlan10`; or
- the default route through `10.10.10.1`.

Stop if a plan proposes replacement or destructive change to any item in that
list. Run `snapshot` before every apply. Its export contains secrets; archive
it outside the repository with owner-only access.

`ether1` is confirmed to have no link. The managed state disables it and uses
the comment `unused`; it is not a current recovery path.

## Perform the one-time bootstrap

Run these steps as `admin` against the already reachable RouterOS 7.16.2
device.

1. Create a backup and sensitive export before changing the device:

   ```text
   /system backup save name=pre-v2
   /export show-sensitive file=pre-v2
   ```

   Download `pre-v2.backup` and `pre-v2.rsc` from the RouterOS Files view and
   archive them outside every repository. Confirm that both downloaded files
   are non-empty before continuing.

2. Create the service group and user:

   ```text
   /user group add name=tofu-svc policy=read,write,api,rest-api
   /user add name=svc-tofu group=tofu-svc address=10.10.10.0/24,192.168.1.0/24,100.64.0.0/10 disabled=yes
   ```

   Set a generated password for `svc-tofu` through the authenticated RouterOS
   user-management interface, then enable the account. Do not add `ssh`, `ftp`,
   `winbox`, `policy`, `password`, or `sensitive` to the group. RouterOS 7.16
   requires the `api` policy for REST authentication; this policy does not
   enable the binary `api` service. The account is for REST access, not
   interactive administration.

3. In `GilmanLab/secrets`, create
   `network/sw-core01/terraform.sops.yaml` through SOPS with these entries:

   - `username`: `svc-tofu`;
   - `password`: the generated service-account password; and
   - `admin_password`: a newly rotated `admin` break-glass password.

   Rotate the RouterOS `admin` password to the stored `admin_password`. Keep the
   service and break-glass passwords different. Do not decrypt the file to
   disk or print either value.

4. Create a device-local CA, sign the HTTPS leaf, and bind the leaf to
   `www-ssl`:

   ```text
   /certificate add name=sw-core01-ca common-name=sw-core01-ca days-valid=3650 key-usage=key-cert-sign,crl-sign
   /certificate sign sw-core01-ca
   /certificate add name=sw-core01-tls common-name=sw-core01 subject-alt-name=IP:10.10.10.2 days-valid=1095 key-usage=digital-signature,key-encipherment,tls-server
   /certificate sign sw-core01-tls ca=sw-core01-ca
   /ip service set www-ssl certificate=sw-core01-tls disabled=no address=10.10.10.0/24,192.168.1.0/24,100.64.0.0/10
   /certificate export-certificate sw-core01-ca file-name=sw-core01-ca
   /certificate print detail where name=sw-core01-ca
   /certificate print detail where name=sw-core01-tls
   ```

   The CA must be self-signed. The leaf must report `common-name=sw-core01`,
   `subject-alt-name=IP:10.10.10.2`, and `ca=sw-core01-ca`.

   Download the resulting public `sw-core01-ca.crt` from RouterOS Files to
   `routeros/sw-core01/certs/sw-core01-ca.crt`. Do not specify an export
   passphrase: RouterOS then exports the public certificate without the private
   key. Review and commit only the public CA `.crt` file in the networking
   change.

   Confirm the exported trust anchor before committing it:

   ```bash
   openssl x509 -in routeros/sw-core01/certs/sw-core01-ca.crt \
     -noout -subject -issuer
   ```

   Both subject and issuer must identify `sw-core01-ca` as the common name.

5. Verify the same TLS and authentication contract that the provider will use:

   ```bash
   (
     export ROS_USERNAME="$(sops -d --extract '["username"]' \
       "$GLAB_SECRETS_DIR/network/sw-core01/terraform.sops.yaml")"
     export ROS_PASSWORD="$(sops -d --extract '["password"]' \
       "$GLAB_SECRETS_DIR/network/sw-core01/terraform.sops.yaml")"
     curl --fail --silent --show-error \
       --cacert routeros/sw-core01/certs/sw-core01-ca.crt \
       --user "$ROS_USERNAME:$ROS_PASSWORD" \
       https://10.10.10.2/rest/system/resource >/dev/null
   )
   ```

   Success is an HTTP 200 response and a zero exit status. This gate confirms
   the leaf's `SAN IP:10.10.10.2` identity, the pinned CA trust path, REST
   reachability, and the `tofu-svc` policy. Stop before any OpenTofu operation
   if it fails.

6. Enable and restrict the interactive management services used for snapshots
   and break-glass access:

   ```text
   /ip service set ssh disabled=no address=10.10.10.0/24,192.168.1.0/24,100.64.0.0/10
   /ip service set winbox disabled=no address=10.10.10.0/24,192.168.1.0/24,100.64.0.0/10
   ```

   Tailnet clients present addresses from `100.64.0.0/10` because `gw01` runs
   Tailscale with `--snat-subnet-routes=false`. Keep the same three allowed
   source ranges on `www-ssl`, `ssh`, and `winbox`.

7. Remove the legacy `crs309.mgmt.lab.gilman.io` certificate only after the
   pinned REST check succeeds. Confirm the `admin` break-glass login and, before
   the purge phase, physically verify whether this chassis has a usable serial
   console.

## Plan and apply a routine change

Pull-request CI runs `just check`, which performs only `tofu fmt -check`,
`tofu init -backend=false`, and `tofu validate`. GitHub-hosted runners cannot
route to `10.10.10.2`; merging a change does not plan against or apply to the
device.

1. Initialize the root after a fresh checkout or backend change:

   ```bash
   just -f routeros/sw-core01/Justfile init
   ```

2. Download the current sensitive export immediately before planning and
   applying:

   ```bash
   just -f routeros/sw-core01/Justfile snapshot
   ```

   The recipe writes `routeros/sw-core01/pre-apply.rsc` by running
   `/export show-sensitive file=pre-apply` over SSH and copying the file from
   the device. Move the file to a dated, access-controlled location outside the
   repository. Do not continue if SSH or SCP fails.

3. Create the saved plan:

   ```bash
   just -f routeros/sw-core01/Justfile plan
   tofu -chdir=routeros/sw-core01 show tfplan
   ```

   Review every action. Stop on unexplained drift, any replacement, or any
   management-path change. A routine plan must not contain imports left from
   the one-time adoption.

4. Apply only the reviewed saved plan:

   ```bash
   just -f routeros/sw-core01/Justfile apply
   ```

5. Run a new plan. It must report no changes:

   ```bash
   just -f routeros/sw-core01/Justfile plan
   ```

## Record and perform the cutover

Keep a cutover record with the operator, start and finish times, downloaded
backup and export paths, plan summary, commands or change commit, verification
results, and outcome for every phase below. Do not combine phases if doing so
would remove a verification gate.

| Phase | Procedure and required record |
| --- | --- |
| **P0 — Snapshot** | Save and download a RouterOS backup and sensitive export. Record their local paths and hashes. Repeat `just snapshot` before each later OpenTofu apply. |
| **P1 — Bootstrap auth/TLS** | Complete the bootstrap above. Record the secret-file revision, public CA certificate fingerprint, REST gate result, and tested break-glass path without recording plaintext secrets. |
| **P2 — Adopt** | Run `init`, `snapshot`, and the adoption plan. The plan may contain imports and in-place updates, but no replacements. Import the existing bridge, five bridge-port rows, VLAN 10 and 40 rows, `mgmt-vlan10`, static address, default route, services, and `tofu-svc` group. Remove `imports.tf` after the successful adoption apply. Record the saved-plan summary and empty follow-up plan. |
| **P3 — Low-risk convergence** | Apply identity, factory interface names and comments, service hardening, DNS, route, and NTP client configuration. Record the before and after service state. The NTP client uses `10.10.10.1`. |
| **P4 — Purge v1 remnants** | Use a separate interactive `admin` SSH session with Safe Mode engaged. Remove VLAN rows 30, 50, and 60, `192.168.88.1/24`, and the defconf `bridge` port rows and bridge. Verify the management path from a second session before leaving Safe Mode. |
| **P5 — Complete port set** | Run `snapshot`, plan, and apply to create the `bridge-lab` rows for `sfp-sfpplus5` through `sfp-sfpplus7`. Confirm `ether1` is disabled with comment `unused`. |
| **P6 — Verify and record** | Require an empty plan, compare a fresh export with the reviewed expected state, run link and VLAN checks, and archive a fresh post-cutover backup and export. Record every expected unmanaged line. |

The safety property for the whole sequence is unchanged: `bridge-lab`, its
`sfp-sfpplus8` port, the VLAN 10 row, `mgmt-vlan10`, `10.10.10.2/24`, and the
default route remain adopted in place.

### Purge v1 remnants in Safe Mode

1. Start a separate interactive SSH session as `admin` and press **Ctrl+X**.
   Confirm that the prompt shows `SAFE` before changing anything.
2. Inspect each target, then remove only the abandoned objects:

   ```text
   /interface bridge vlan print detail where vlan-ids=30
   /interface bridge vlan print detail where vlan-ids=50
   /interface bridge vlan print detail where vlan-ids=60
   /interface bridge vlan remove [find where vlan-ids=30]
   /interface bridge vlan remove [find where vlan-ids=50]
   /interface bridge vlan remove [find where vlan-ids=60]
   /ip address print detail where address="192.168.88.1/24"
   /ip address remove [find where address="192.168.88.1/24"]
   /interface bridge port print detail where bridge="bridge"
   /interface bridge port remove [find where bridge="bridge"]
   /interface bridge print detail where name="bridge"
   /interface bridge remove [find where name="bridge"]
   ```

   Stop if a `find` expression selects an unexpected object. These removals are
   outside the VLAN 10 management path.
3. From a second session, verify HTTPS, SSH, the default route, VLAN 10, and the
   `sfp-sfpplus8` link. If access fails, terminate the Safe Mode session without
   leaving Safe Mode so RouterOS reverts its terminal-session changes.
4. When verification succeeds, press **Ctrl+X** in the Safe Mode session to
   keep the changes. Proceed to P5.

The accepted architecture permits an optional one-shot scheduler that enables
`ether1` and restores a temporary emergency static address ten minutes after
P4. Do not rely on it while `ether1` remains confirmed no-link. If the port is
repaired, test the exact recovery address and scheduler on an isolated session,
record both in the cutover record, and remove the scheduler immediately after
P4 succeeds.

### Apply the adopt-versus-purge rule

- Adopt every live object that also belongs in the v2 desired state. Use the
  reviewed `imports.tf` import blocks for the one-time adoption, then remove the
  blocks after the successful adoption apply.
- Purge every v1 object with no v2 future instead of importing it only to
  destroy it. This set includes the defconf `bridge`, its port rows,
  `192.168.88.1/24`, VLAN rows 30, 50, and 60, and the legacy
  `crs309.mgmt.lab.gilman.io` certificate.
- Prove the result with an empty plan and a post-cutover sensitive export. Run
  `/export show-sensitive file=post-cutover`, download the file outside the
  repository, and compare it with the reviewed expected export:

  ```bash
  diff -u -- "$EXPECTED_EXPORT" "$POST_CUTOVER_EXPORT"
  ```

  Set both variables to the corresponding access-controlled archive paths.
  Every remaining unmanaged line must be an expected user, certificate,
  backup, or RouterOS default.

## Verify the managed state

After cutover or a routine apply, confirm all of the following:

- `just -f routeros/sw-core01/Justfile plan` reports no changes.
- `www-ssl`, `ssh`, and `winbox` are enabled and restricted to
  `10.10.10.0/24,192.168.1.0/24,100.64.0.0/10`.
- `www`, `ftp`, `telnet`, `api`, and `api-ssl` are disabled.
- the NTP client is enabled with server `10.10.10.1`.
- `ether1` is disabled with comment `unused` and still reports no link.
- the VLAN 10 management path and VLAN 40 trunk match the
  [address and VLAN plan](../reference/networking/address-plan.md).
- the `curl` REST gate still succeeds with the pinned CA certificate.

Create and download a post-change export. Diff it against the pre-change export
and the reviewed intended changes. RouterOS users, passwords, the TLS
certificate and private key, backups, and device defaults are intentionally
outside OpenTofu; every other unexplained line is drift that must be resolved
or recorded before another apply.

Run a live plan before every configuration change and after every RouterOS
upgrade. Run an additional plan whenever manual device access may have changed
configuration. CI does not perform drift checks.

## Recovery

- If the provider credential or pinned certificate fails but the management
  path remains reachable, log in with the rotated `admin` break-glass
  credential. Repair the user, group, service ACL, or certificate through the
  bootstrap procedure, then repeat the pinned REST gate before running a plan.
- If P4 disconnects the device while Safe Mode is still active, terminate that
  session and allow RouterOS to revert the terminal-session changes. Safe Mode
  cannot revert an OpenTofu REST apply.
- If a committed cutover cannot be repaired in place, upload the archived
  `.backup` file through RouterOS Files and load it with the RouterOS system
  backup restore operation. The restore reboots the switch. Re-run the REST
  gate and a live plan after access returns.
- If normal management is unavailable, use the CRS309 reset-button recovery
  path and restore the downloaded backup. A serial console is a possible
  last-resort path, but its presence on this CRS309 has not been verified;
  confirm the hardware before treating it as recovery coverage.

Escalate and stop the cutover when a plan replaces a management-path resource,
the pinned REST gate fails, a backup or export cannot be downloaded, Safe Mode
selects unexpected objects, or no tested break-glass path remains.
