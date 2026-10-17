---
title: Deploy and use the Windows VM
description: Install win01 unattended on lab02, connect over Remote Desktop, activate it, and recover it.
---

# Deploy and Use the Windows VM

`win01` is a Windows 11 Pro desktop VM on `lab02`, used over Remote Desktop.
It sits on the services VLAN at `10.10.50.30`, so home and tailnet clients
reach it through `gw01`. The OpenTofu root is `GilmanLab/fleet`
`incus/windows/`; its README lists the devices and the install media design.

| Access | Value |
| --- | --- |
| Remote Desktop | `10.10.50.30` |
| Administrator | `josh`, password in `GilmanLab/secrets` `services/windows/win01.sops.yaml` |

## Preconditions

- `nas01:` Incus remote with the operator client certificate. The OpenTofu
  provider on macOS needs
  `INCUS_CONF="$HOME/Library/Application Support/incus"`.
- `AWS_PROFILE=lab-admin` with a live SSO session (state backend and SOPS).
- `lab02` `fast50` converged by `fleet-cluster network`, and VLAN 50 tagged on
  `sw-core01` `bond-lab02` (`GilmanLab/networking`).
- A Windows 11 multi-edition ISO from
  <https://www.microsoft.com/software-download/windows11> and the stable
  `virtio-win.iso` from
  <https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/>.
- A Windows 11 **Pro** licence. Home cannot host Remote Desktop.

## Safety impact

Creating the VM touches only `lab02`. The instance has `prevent_destroy`; a
`tofu destroy` fails rather than deleting the installed system disk. The
unattend ISO wipes the VM's own disk 0 only, and only while the install media
are attached. Never attach the VM to `fast40`: a macvlan there breaks
`lab02`'s OVN gateway.

## Install

From `GilmanLab/fleet` `incus/windows/`:

```bash
export AWS_PROFILE=lab-admin GLAB_AWS_STATE_BUCKET=glab-lab-tfstate-186067932323
export INCUS_CONF="$HOME/Library/Application Support/incus"
just init
just stage-install-media ~/Downloads/win11.iso ~/Downloads/virtio-win.iso \
  ~/code/glab/secrets/services/windows/win01.sops.yaml
just plan -var running=false -var install_media=true && just apply
incus config set nas01:win01 image.os=Windows
just plan -var install_media=true && just apply
```

Setup reboots several times and finishes in about 20 minutes. It is done when
Remote Desktop answers:

```bash
nc -z -w 5 10.10.50.30 3389 && echo ready
```

Then detach and delete the install media:

```bash
just plan && just apply
just remove-install-media
```

## Connect

1. Copy the password:

   ```bash
   AWS_PROFILE=lab-admin sops decrypt --extract '["win01"]["admin_password"]' \
     ~/code/glab/secrets/services/windows/win01.sops.yaml | pbcopy
   ```

2. In the Windows App (Microsoft Remote Desktop) on macOS, add PC
   `10.10.50.30`, user `josh`, and paste the password.

The media library is available read-only at `\\10.10.50.20\media` with the
`media` account from the media stack runbook.

## Activate

**Settings → System → Activation → Change product key**, enter the purchased
Windows 11 Pro key. The install uses Microsoft's generic Pro key, which selects
the edition but never activates.

## Recovery

- No Remote Desktop after install: `C:\win01-setup.log` records the
  first-logon script. Without a working session, open the graphical console
  with `remote-viewer` installed. On macOS the default Incus config path
  contains a space, which `remote-viewer` cannot open, so point
  `INCUS_CONF` at a symlink:

  ```bash
  ln -sfn "$HOME/Library/Application Support/incus" /tmp/incusconf
  INCUS_CONF=/tmp/incusconf incus console nas01:win01 --type=vga
  ```

- Watch the firmware during install with
  `incus console nas01:win01 --show-log`. The system disk boots first; on an
  empty disk the firmware logs `NVMe ... Not Found` and starts the installer
  from USB. `Time out` on the USB entry means the ISO was not staged through
  `just stage-install-media`, which removes the "Press any key" prompt.
- Restart an interrupted install: an install stopped part-way leaves files on
  the disk, and Setup then stops at "It looks like you started an upgrade"
  before reading the answer file. Wipe the system disk and boot again;
  `rebuild` clears `image.os`, so set it again:

  ```bash
  incus stop -f nas01:win01
  incus rebuild nas01:win01 --empty
  incus config set nas01:win01 image.os=Windows
  incus start nas01:win01
  ```

## Escalate

- `nc` to `10.10.50.30:3389` fails from home but the VM is running: check the
  VLAN 50 tag on `bond-lab02` and the `fast50` interface on `lab02`
  (`incus query "nas01:/os/1.0/system/network?target=lab02"`).
