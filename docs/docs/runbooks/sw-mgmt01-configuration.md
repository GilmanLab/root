---
title: Manage the sw-mgmt01 configuration
description: Inspect, change, back up, verify, and recover the hand-managed sw-mgmt01 configuration.
---

# Manage the sw-mgmt01 configuration

Use this runbook to inspect, change, back up, or recover `sw-mgmt01`. The
procedure and desired state were verified live on 2026-08-20 against a TRENDnet
TEG-3102WS v1.0R running firmware `IMG-3.01.347`.

`sw-mgmt01` is a hand-managed appliance. No automation or
infrastructure-as-code surface exists for this device class. Its authoritative
configuration record combines the desired-state table in this runbook with
the encrypted `network/sw-mgmt01/config-backup.sops.yaml` backup in
`GilmanLab/secrets`.
This differs from the OpenTofu-managed `sw-core01` root.
[ADR-0004](../decisions/0004-manage-routeros-devices-with-opentofu.md)
applies to RouterOS devices, not this TRENDnet switch.

The [network address and VLAN plan](../reference/networking/address-plan.md) is
the canonical source for addresses, VLANs, and switch port roles.

## Preconditions and required access

- Connect through a trusted path that can reach VLAN 70. The management address
  is `http://10.10.70.2/`; the switch has no CLI or SSH service.
- Obtain the `admin` credential from
  `GilmanLab/secrets` `network/sw-mgmt01/admin.sops.yaml` with approved SOPS
  access.
- For API or backup operations, install `curl` and `jq`. For backup inspection
  and escrow, also install `tar`, `base64`, SOPS, and Moon 2.x.
- Use a current `GilmanLab/secrets` checkout and the `lab-admin` AWS profile for
  routine SOPS access.
- Confirm that no other operator is changing the switch.

The management interface is a React single-page application over HTTP. The
browser and the JSON API send the credential and bearer token without transport
encryption. Use them only across the trusted management path. Do not expose the
management address through an untrusted proxy or network.

## Safety impact

Changing the management interface, the VLAN 70 membership on port 1, or the
port 1 trunk can disconnect the only management path. A saved change survives a
reboot; this behavior was proven on the device. Keep access to `gw01` before any
management-path change so that the factory-address bootstrap path remains
available.

The JSON API can return `errCode: 0` and an `OK` message for a malformed write
body without applying the change. **Read back the affected endpoint after every
write and compare the returned state with the intended state.** Do not treat the
HTTP status or `errCode: 0` as proof that a write succeeded.

## Desired state

The live and saved configuration has this management interface:

| Setting | Value |
| --- | --- |
| Canonical name | `sw-mgmt01` |
| Address | `10.10.70.2/24` |
| Management VLAN | `70` |
| Default gateway | `10.10.70.1` |

The live and saved VLAN membership is:

| VLAN ID | Name | Tagged ports | Untagged ports |
| --- | --- | --- | --- |
| `10` | `MGMT` | `1` | `2`, `4`, `6`, `8` |
| `70` | `OOB` | `1` | `3`, `5`, `7` |
| `1` | `default` | — | `9`–`10`, `t1`–`t8` |

Ports `9`–`10` are unused SFP slots. `t1`–`t8` are unused link-aggregation
placeholders. VLAN 1 is untagged only on those unused entries; it is not an
access VLAN for ports `1`–`8`.

The configured PVIDs are:

| Ports | PVID | Role |
| --- | --- | --- |
| `1` | `1` | 802.1Q trunk to `gw01`; tagged VLANs 10 and 70 |
| `2`, `4`, `6`, `8` | `10` | Management access ports |
| `3`, `5`, `7` | `70` | OOB access ports |

The endpoint assignment for ports `1`–`8` matches the
[`sw-mgmt01` port map](../reference/networking/address-plan.md#sw-mgmt01).

## Use the web interface

Use the web interface for routine administration:

1. Browse to `http://10.10.70.2/` from a trusted management path.
2. Sign in as `admin` with the credential from `GilmanLab/secrets`.
3. Compare the management interface, VLAN rows, and port PVIDs with the desired
   state above before changing anything.
4. Make one logical change at a time.
5. Read the changed page again and compare every affected field with the
   intended state.
6. Use the interface's save operation only after the running state is correct.
7. Sign out or close the management session when finished.

Do not infer success from a confirmation message alone. The web interface uses
the same JSON API that accepts some malformed writes without applying them.

## Use the JSON API

The web interface uses an unofficial but stable JSON API. It is suitable for
operator and agent-assisted inspection and carefully supervised changes, but it
is not an infrastructure-as-code interface.

Set the API base URL, then authenticate. The login response contains a bearer
JWT that is valid for 300 seconds. The following Bash commands avoid placing
the password in the command line:

```bash
export SW_MGMT01_URL=http://10.10.70.2
read -rsp 'sw-mgmt01 admin password: ' SW_MGMT01_PASSWORD
echo
LOGIN_RESPONSE="$({
  jq -nc --arg password "$SW_MGMT01_PASSWORD" \
    '{user:"admin",password:$password}'
} | curl --fail-with-body --silent --show-error \
  --request PATCH \
  --header 'Content-Type: application/json' \
  --data-binary @- \
  "$SW_MGMT01_URL/api/system/login")"
unset SW_MGMT01_PASSWORD
printf '%s\n' "$LOGIN_RESPONSE" | jq .
read -rsp 'JWT from the login response: ' SW_MGMT01_TOKEN
echo
unset LOGIN_RESPONSE
```

Send `Authorization: Bearer $SW_MGMT01_TOKEN` on authenticated requests. Log in
again when the 300-second token expires.

The verified API surface is:

| Method and path | Request and response contract |
| --- | --- |
| `PATCH /api/system/login` | Send `{"user":"admin","password":"..."}`. The response supplies the bearer JWT. |
| `GET /api/system/settings/mgmtinterface` | Read the management-interface state. |
| `PATCH /api/system/settings/mgmtinterface` | Send one **flat object** with `vlanID`, `configuration`, `IP`, `submask`, `defaultGateway`, `dns1IP`, `dns2IP`, and `dhcpOption43`. A wrapped object is silently ignored even though the response reports `errCode: 0`. |
| `GET /api/customize_vlan` | Read the VLAN rows. |
| `PATCH /api/customize_vlan` | Send an **array of VLAN rows**. Each row has `vlanID`, `vlanName`, `tagged_ports`, `untagged_ports`, `forbidden_ports`, and `advertise_state`. A single row object is silently ignored. |
| `GET /api/ports` | Read port state, including the configured PVIDs. |
| `POST /api/system/save` | Persist the running configuration. Saved changes have survived a reboot in live verification. |
| `GET /api/system/config/backup` | Return `backupURL` and `fileName` for a generated configuration backup. Download `http://10.10.70.2/<backupURL>` with the same bearer header. |

Read all configuration surfaces before a change:

```bash
curl --fail-with-body --silent --show-error \
  --header "Authorization: Bearer $SW_MGMT01_TOKEN" \
  "$SW_MGMT01_URL/api/system/settings/mgmtinterface" | jq .
curl --fail-with-body --silent --show-error \
  --header "Authorization: Bearer $SW_MGMT01_TOKEN" \
  "$SW_MGMT01_URL/api/customize_vlan" | jq .
curl --fail-with-body --silent --show-error \
  --header "Authorization: Bearer $SW_MGMT01_TOKEN" \
  "$SW_MGMT01_URL/api/ports" | jq .
```

For a write, create a JSON file with exactly the body shape in the table. Send
the file, then immediately repeat the corresponding `GET` and compare the
result field by field. For example, a management-interface write uses a flat
object in `mgmtinterface.json`:

```bash
curl --fail-with-body --silent --show-error \
  --request PATCH \
  --header "Authorization: Bearer $SW_MGMT01_TOKEN" \
  --header 'Content-Type: application/json' \
  --data-binary @mgmtinterface.json \
  "$SW_MGMT01_URL/api/system/settings/mgmtinterface" | jq .
curl --fail-with-body --silent --show-error \
  --header "Authorization: Bearer $SW_MGMT01_TOKEN" \
  "$SW_MGMT01_URL/api/system/settings/mgmtinterface" | jq .
```

A VLAN write uses the same pattern with an array in `vlans.json` and the
`/api/customize_vlan` endpoint. Do not send only the changed row as an object.
After all readbacks match the intended state, persist the configuration:

```bash
curl --fail-with-body --silent --show-error \
  --request POST \
  --header "Authorization: Bearer $SW_MGMT01_TOKEN" \
  "$SW_MGMT01_URL/api/system/save" | jq .
```

Remove local request files after the operation. They are temporary operator
material, not a version-controlled configuration source.

## Back up and escrow the configuration

Create a new backup after every saved configuration change:

1. Log in and set `SW_MGMT01_TOKEN` as described above.
2. Request a backup and download the returned file with the bearer header:

   ```bash
   BACKUP_RESPONSE="$(curl --fail-with-body --silent --show-error \
     --header "Authorization: Bearer $SW_MGMT01_TOKEN" \
     "$SW_MGMT01_URL/api/system/config/backup")"
   BACKUP_URL="$(printf '%s' "$BACKUP_RESPONSE" | jq -er '.backupURL')"
   BACKUP_FILE="$(printf '%s' "$BACKUP_RESPONSE" | jq -er '.fileName')"
   curl --fail-with-body --silent --show-error \
     --header "Authorization: Bearer $SW_MGMT01_TOKEN" \
     --output "$BACKUP_FILE" \
     "${SW_MGMT01_URL%/}/${BACKUP_URL#/}"
   test -s "$BACKUP_FILE"
   unset BACKUP_RESPONSE BACKUP_URL SW_MGMT01_TOKEN
   ```

3. Inspect the archive before escrow:

   ```bash
   tar -tf "$BACKUP_FILE"
   tar -xOf "$BACKUP_FILE" current_config/SNCSR.conf | less
   ```

   The `.cfg` is a `ustar` archive. Its `current_config/SNCSR.conf` member is
   plaintext CLI configuration and contains no credentials. Treat the archive
   as durable recovery material and escrow it even though the inspected
   configuration has no credential.

4. From the `GilmanLab/secrets` checkout, encode the `.cfg` as one base64 line
   and replace the stored backup value through SOPS:

   ```bash
   base64 < "$BACKUP_FILE" | tr -d '\n'
   AWS_PROFILE=lab-admin sops network/sw-mgmt01/config-backup.sops.yaml
   ```

   Do not commit the downloaded `.cfg` or its plaintext base64 representation.

5. Verify that the encrypted file has the required recipients and encryption
   context:

   ```bash
   moon run root:check
   ```

   Stop if the metadata check fails. Review and merge the secrets change
   through the normal pull-request flow before considering the backup escrowed.

## Reach a factory-reset switch

The switch is now reachable only through VLAN 70. After a factory reset, its
address is `192.168.10.200`, and the home LAN cannot route
`192.168.10.0/24`. Add a temporary, running-only address to `gw01` and tunnel
the web session through it:

1. On `gw01`, add the temporary address without saving it:

   ```text
   configure
   set interfaces ethernet eth3 address 192.168.10.5/24
   commit
   exit
   ```

2. From the operator workstation, forward a local HTTP port through `gw01`:

   ```bash
   ssh -N -L 127.0.0.1:8200:192.168.10.200:80 vyos@10.10.10.1
   ```

3. Browse to `http://127.0.0.1:8200/` and complete the required bootstrap or
   restore. Keep the SSH session open until finished.
4. Remove the temporary address from `gw01`, then save the clean configuration:

   ```text
   configure
   delete interfaces ethernet eth3 address 192.168.10.5/24
   commit
   save
   exit
   ```

5. Stop the SSH port forward and verify that `192.168.10.5/24` is absent from
   both the running and saved `gw01` configuration.

Never save `gw01` while the temporary factory-access address is present.

## Verification

After any configuration operation, confirm all of the following through fresh
API reads or newly loaded web pages:

- the management interface is VLAN 70 at `10.10.70.2/24` with gateway
  `10.10.70.1`;
- VLANs 1, 10, and 70 match the desired-state table;
- port PVIDs match the desired-state table;
- port 1 still reaches `gw01` and the management page reloads from
  `http://10.10.70.2/`;
- each endpoint on ports `2`–`8` remains reachable on its assigned management
  or OOB VLAN; and
- a newly generated backup downloads as a non-empty archive containing
  `current_config/SNCSR.conf`.

## Recovery and escalation

If the running configuration is wrong but management remains reachable, restore
the intended values one logical change at a time, read back every write, save,
and create a new escrowed backup.

If management is unreachable or the configuration cannot be repaired in place:

1. Use the front-panel reset button to restore factory defaults.
2. Reach `192.168.10.200` through the temporary `gw01` address and SSH port
   forward described above.
3. Decrypt and base64-decode the escrowed
   `network/sw-mgmt01/config-backup.sops.yaml` value into the original `.cfg`
   file outside every repository.
4. In the web interface, open **Tools > Backup/Restore** and restore the `.cfg`.
5. Reconnect at `http://10.10.70.2/`, complete the verification checklist, and
   remove the temporary `gw01` address.

The API upload endpoint `/cgi-bin/data.cgi?cfg_upload` has not been tested. Do
not use it as the primary recovery path. If the web restore fails, or the
switch does not return at either `192.168.10.200` or `10.10.70.2`, stop and
escalate to physical inspection rather than repeating resets or unverified API
uploads.
