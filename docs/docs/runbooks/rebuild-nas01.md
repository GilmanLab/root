---
title: Rebuild nas01
description: Reinstall IncusOS on nas01 from git-defined install media and restore it as the cluster bootstrap node.
---

# Rebuild nas01

Rebuild `nas01` from scratch: seeded IncusOS install media built from
`GilmanLab/fleet`, written to USB, installed onto the 128GB system drive, and
the machine restored as the Incus cluster's first member. This procedure was
proven live on 2026-08-20.

## Preconditions and required access

- `GilmanLab/fleet` checkout (`nodes/nas01/config.yaml` is the seed source).
- `incusos-builder` (build from source per the fleet README until a release
  exists).
- A sacrificial USB stick (raw `dd` target) and brief physical access to
  `nas01`. The PiKVM chain (`pikvm01` → `kvm01` input `nas01`) provides
  remote console and keyboard; mass-storage emulation through `kvm01` does
  NOT work (USB 1.1 enumeration) and ATX is not wired — media insertion and
  power-cycling are physical.
- `lab-admin` AWS SSO for SOPS (recovery-key escrow in `GilmanLab/secrets`).
- The trusted Incus client keypair (`bootstrap-admin`); its public half is in
  the seed, its private half escrowed at `fleet/shared/bootstrap-client` in
  `GilmanLab/secrets`.

## Safety impact

- Destroys everything on `nas01`'s 128GB system drive (RS128GSSD510). The
  seed's `install.target` (`bus: NVME`, `max_size: 200GiB`) cannot select the
  1TB data drives.
- The machine's previous disk-encryption recovery keys become invalid; new
  ones are generated at first boot and MUST be re-escrowed (step 8).
- If `nas01` hosts cluster workloads, they are lost unless recovered by their
  own means — this runbook covers the node, not workload data.

## Procedure

1. Build the media (any machine with the builder):

   ```sh
   incusos-builder validate -f nodes/nas01/config.yaml
   incusos-builder build -f nodes/nas01/config.yaml -o nas01.img
   ```

   Record the reported IncusOS version and sha256. Pin `image.release` in the
   config if updating it.
2. Write the image raw to a USB stick (macOS shown; never write through
   Ventoy — chain-loading alters the measured boot path):

   ```sh
   diskutil list                    # identify the stick, carefully
   diskutil unmountDisk /dev/diskN
   sudo dd if=nas01.img of=/dev/rdiskN bs=16m
   diskutil eject /dev/diskN
   ```

3. If the previous install is being replaced because of TPM/unseal problems,
   or the TPM's history is unknown: **clear the fTPM in BIOS first**
   (Security → fTPM → clear; the machine reboots). A stale TPM state causes
   the first boot to demand a recovery key it may not have.
4. If a previous IncusOS install exists on the system drive and this rebuild
   is intentional, wipe it first (boot the Ventoy recovery stick, then
   `wipefs -af` + `sgdisk --zap-all` the RS128 device) — otherwise the
   installer refuses (`force_install` is deliberately not set in the seed).
   Never leave install media written to an internal drive: it pollutes the
   measured boot path (PCR4) and leaves a rogue boot entry.
5. Insert the stick, boot the machine (F7 for the boot menu if needed). The
   install is unattended: it selects the 128GB drive, installs, and displays
   "remove the install media to complete the installation".
6. Remove the stick. The machine reboots into IncusOS: the console (PiKVM)
   shows `nas01.glab.lol`, recovery-key generation, and
   `Network configuration: mgmt(10.10.10.14)`.
7. Trust and re-cluster from an operator machine (the seeded client
   certificate is already trusted by the node):

   ```sh
   # Verify the fingerprint against the console's
   # "Application TLS certificate fingerprint" line before accepting.
   incus remote add nas01 10.10.10.14
   incus config set nas01: cluster.https_address=10.10.10.14:8443
   incus cluster enable nas01: nas01
   # Enabling clustering regenerates the server certificate:
   incus remote remove nas01 && incus remote add nas01 10.10.10.14
   ```

8. **Escrow the new recovery keys immediately** (before any workload or
   reboot):

   ```sh
   incus admin os system security show nas01:
   ```

   Write `config.encryption_recovery_keys[0]` and
   `state.pool_recovery_keys.local` into
   `GilmanLab/secrets` `fleet/nas01/incusos.sops.yaml` (SOPS; `fleet` scope)
   and merge through the normal PR flow.

## Verification

- `incus cluster list nas01:` shows `nas01` as `database-leader`, `ONLINE`,
  "Fully operational".
- `incus storage list nas01:` shows the `local` ZFS pool; `incus launch
  images:alpine/3.22 nas01:smoke1`, exec into it, ping `10.10.10.1`, delete.
- Reboot survival: `incus admin os system reboot nas01:` (confirm), machine
  returns within ~3 minutes, `security show` reports both volumes
  `unlocked (TPM)` — no passphrase prompt on console.

## Rollback / recovery

- Boot prompts for a passphrase/recovery key: enter the escrowed
  `encryption_recovery_key` from `GilmanLab/secrets`, then force-reset the
  TPM bindings via the system security API. If no valid key exists (e.g.
  first boot never completed), treat the install as failed: clear the fTPM
  and reinstall from step 3.
- Installer refuses ("already installed"): expected safety behavior; see
  step 4.
- Console access at any point: PiKVM at `https://10.10.70.20/` (input
  `nas01` on the KVM), including a snapshot API and HID keyboard injection.

## Escalation

- TPM unseal failures that survive an fTPM clear + clean reinstall: check
  the IncusOS forum/issues (fTPM quirks are hardware-specific) before
  changing Secure Boot key state. Do not reset Secure Boot to Setup Mode
  casually — the firmware's vendor certificates are involved in the boot
  chain.
