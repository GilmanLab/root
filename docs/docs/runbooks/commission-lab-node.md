---
title: Commission a lab compute node
description: Provision AMT, install seeded IncusOS from USB, join the cluster, and escrow recovery keys for an MS-02 lab node.
---

# Commission a lab compute node

Bring a Minisforum MS-02 Ultra lab node (`lab01`–`lab03` class) from bare or
previously-used hardware to an ONLINE Incus cluster member. This procedure was
proven live on 2026-08-21 (session 009) against all three lab nodes and AMI
BIOS `2.22.0059` with Intel ME `19.0.5`.

The [network address and VLAN plan](../reference/networking/address-plan.md) is
canonical for every address used here. Seed configuration lives in
`GilmanLab/fleet` `nodes/<name>/config.yaml`.

## Preconditions and required access

- A `GilmanLab/fleet` config for the node with its **verified** 10GbE
  management NIC MAC (`strict_hwaddr` binding; a wrong MAC leaves the node
  unreachable after install). See "Harvest the management MAC" below.
- `incusos-builder` at the pin recorded in the fleet README, and a sacrificial
  USB stick. Install media MUST be a raw image written with `dd`; never boot
  the installer through Ventoy, and never attempt an AMT IDER/USB-R boot (see
  Safety impact).
- `lab-admin` AWS SSO for SOPS: the node's AMT credential
  (`fleet/<name>/amt.sops.yaml`) and recovery-key escrow
  (`fleet/<name>/incusos.sops.yaml`) in `GilmanLab/secrets`.
- The trusted `bootstrap-admin` Incus client keypair (public half is in every
  seed).
- Physical access for MEBx configuration, power, and USB insertion. AMT has no
  remote path until MEBx is done, and the chassis has no wired ATX control.
- An AMT client on VLAN 10 for post-provisioning verification and console
  work. gw01 forwards management→OOB in full, but the home→OOB path does not
  pass the AMT service ports; a client on the management VLAN (for example
  the `meshcommander` container on `nas01`, `http://10.10.10.14:3000/`) is
  required.

## Safety impact

- The seed sets `force_install: true`: everything on the node's 128GB system
  drive is destroyed. The `install.target` selector (`bus: NVME`,
  `max_size: 200GiB`) cannot select the 2TB data drive.
- The Secure Boot procedure removes the factory Microsoft/vendor keys. After
  it, only IncusOS-signed media boots on the node with Secure Boot enabled.
- **Never issue "Reset to IDE-R CDROM/Floppy" or attempt an AMT storage-
  redirection boot on this platform.** AMI `2.22.0059` wedges pre-boot with
  black video and dead input (local and remote); only a cold AMT power cycle
  recovers. Reproduced twice in session 009.

## Procedure

### 1. Provision AMT in MEBx

Read the credential first (never store it in MeshCommander's device list):

```sh
cd ~/code/glab/secrets
AWS_PROFILE=lab-admin sops -d --extract '["password"]' fleet/<name>/amt.sops.yaml
```

In BIOS setup → MEBx, all in one visit:

1. Set the AMT admin password to the escrowed value.
2. Network Setup: **static** address per the address plan
   (`10.10.70.11/12/13`, mask `255.255.255.0`, gateway `10.10.70.1`). AMT
   addresses are deliberately not DHCP reservations.
3. Enable SOL, storage redirection, and KVM (Manageability Feature Selection).
4. User Consent → opt-in: **NONE** (headless KVM fails otherwise).
5. Network Access State: **Network Active**.

Settings commit on **Save & Exit**, not live. In the same visit, prepare
Secure Boot (Security → Secure Boot):

1. Secure Boot Mode: Custom.
2. Key Management → **Factory Key Provision: Disabled**. With it enabled the
   firmware silently re-installs factory keys on every reset and the IncusOS
   media keeps failing Secure Boot validation.
3. Key Management → **Reset to Setup Mode** (delete all keys / delete PK).
4. Keep Secure Boot enabled; Save & Exit. The installer auto-enrolls the
   IncusOS PK/KEK/db and the system runs in User Mode afterward.

Verify AMT from a VLAN 10 client: `ping 10.10.70.<n>` and TLS digest auth
(AMT ≥16 is TLS-only — ports 16993/16995; 16992/16994 stay closed by design):

```sh
curl -sk --digest -u "admin:<password>" -o /dev/null \
  -w '%{http_code}\n' https://10.10.70.<n>:16993/index.htm   # expect 200
```

### 2. Harvest the management MAC

The seed binds the management interface by MAC. Two proven methods:

- **PXE-entry read (works on blank machines):** BIOS → Advanced → Network
  Stack: Enabled → Save & Exit → boot menu (F7). Each PXE entry is labeled
  with its NIC's MAC. The entry equal to the AMT MAC is the shared 2.5GbE
  NIC; the other copper entry is the 10GbE management NIC. Disable Network
  Stack again afterward.
- **Old-OS lease (works when a previous OS remains):** boot the resident OS
  and read `show dhcp server leases` on `gw01`; the VLAN 10 lease is the
  management NIC.

Observed pattern on all three MS-02s: management MAC = AMT MAC + 1. Treat it
as a prediction only; verify before building.

Record the MAC in `GilmanLab/fleet` `nodes/<name>/config.yaml` through the
normal PR flow.

### 3. Build and write install media

```sh
incusos-builder validate -f nodes/<name>/config.yaml
incusos-builder build -f nodes/<name>/config.yaml -o <name>.img
diskutil list                    # identify the stick, carefully
diskutil unmountDisk /dev/diskN
sudo dd if=<name>.img of=/dev/rdiskN bs=16m
diskutil eject /dev/diskN
```

Pin `image.release` to the release the cluster is running
(`incus query nas01:/os/1.0 | jq -r .environment.os_version`); joining
members should match the existing members.

### 4. Install

Insert the stick and boot it (F7 if needed). The install is unattended; the
installer waits for media removal, then reboots into IncusOS. The console
shows the hostname, `Applying Secure Boot certificate update`, the
`Application TLS certificate fingerprint`, and the static management address.

If the installer fails with `mkfs.vfat ... contains a mounted filesystem`,
old partition remnants (observed with Proxmox) are colliding: boot a rescue
Linux and wipe **only** the 128GB system drive, then retry:

```sh
lsblk -o NAME,SIZE,MODEL         # verify by size before wiping
wipefs -af /dev/<128GB-disk>
sgdisk --zap-all /dev/<128GB-disk>
```

### 5. Verify identity and escrow recovery keys

Compare the console fingerprint line with the API certificate before trusting
anything:

```sh
echo | openssl s_client -connect 10.10.10.<n>:8443 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256
incus remote add <name> 10.10.10.<n>    # only after the fingerprints match
```

Escrow immediately — before the join and before any reboot test:

```sh
incus query <name>:/os/1.0/system/security
```

Write `config.encryption_recovery_keys[0]` and
`state.pool_recovery_keys.local` into `GilmanLab/secrets`
`fleet/<name>/incusos.sops.yaml` (keys `encryption_recovery_key` and
`zfs_pool_local_recovery_key`) and merge through the normal PR flow. Then
acknowledge retrieval — this clears the console warning and MUST use the
dedicated action endpoint (a plain PUT of the state field is silently
ignored):

```sh
incus query '<name>:/os/1.0/system/security/:retrieved' -X POST
```

### 6. Join the cluster

```sh
TOKEN="$(incus cluster add nas01:<name> | tail -1)"
jq -n --arg cert "$(cat ~/.config/incus/servercerts/nas01.crt)" --arg token "$TOKEN" '{
  server_name: "<name>",
  enabled: true,
  server_address: "10.10.10.<n>:8443",
  cluster_address: "10.10.10.14:8443",
  cluster_certificate: $cert,
  cluster_token: $token,
  member_config: [{entity: "storage-pool", name: "local", key: "source", value: "local/incus"}]
}' | incus query <name>:/1.0/cluster -X PUT --data @-
```

`server_name` is required. The `local` ZFS pool's member source is the
OS-created `local/incus` dataset. Joining adopts the cluster certificate, so
remove the now-stale standalone remote: `incus remote remove <name>`.

## Verification

- `incus cluster list nas01:` shows the node `ONLINE`, "Fully operational".
- Smoke test on the new member:

  ```sh
  incus launch images:alpine/3.22 nas01:smoke-<name> --target <name>
  incus exec nas01:smoke-<name> -- ping -c 2 10.10.10.1
  incus delete -f nas01:smoke-<name>
  ```

- `incus query 'nas01:/os/1.0/system/security?target=<name>'` reports
  `encryption_recovery_keys_retrieved: true`.

## Rollback / recovery

- Boot prompts for a recovery key: use the escrowed
  `encryption_recovery_key` from `GilmanLab/secrets`, then rebind the TPM via
  the system security API.
- A wrong seeded MAC leaves the node unreachable with no shell: fix the fleet
  config and reinstall from step 3.
- AMT/firmware wedge (black video, dead input): AMT Power Actions → power
  down, wait, power up. Do not retry the action that caused it.
- A failed join leaves the node standalone; it can be re-joined with a fresh
  token. If the node joined partially, remove it with
  `incus cluster remove --force` before retrying.

## Escalation

- Secure Boot violations that survive the Factory Key Provision + Setup Mode
  procedure: stop and inspect the firmware's key state; do not disable Secure
  Boot to work around it.
- TPM unseal failures on first boot: clear the fTPM and reinstall (see the
  [nas01 rebuild runbook](rebuild-nas01.md), which documents the same failure
  class).
- Installer refuses or fails after a clean disk wipe: capture the console
  error and check `lxc/incus-os` upstream before retrying.
