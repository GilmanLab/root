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
| SSH (PowerShell, key-only) | `ssh -i ~/.ssh/win01 josh@10.10.50.30` |
| Agent desktop control (Windows-MCP) | `http://10.10.50.30:8000/mcp`, bearer token `win01.windows_mcp_auth_key` |
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

The media library (`\\10.10.50.20\media`) is mapped as drive `M:` and the
download area (`\\10.10.50.20\torrents`) as `T:`, both read-only, and the
writable games folder (`\\10.10.50.20\games`) as `G:`. All three reconnect at
every logon for `josh` and use the `media` account, whose
password from the media stack runbook is saved in Windows Credential Manager
(target
`10.10.50.20`). After a password change, rerun
`cmdkey /add:10.10.50.20 /user:media /pass:<new>` in a desktop session; a
key-authenticated SSH session cannot write to Credential Manager.

For commands, SSH in with the operator key; the session is PowerShell:

```bash
ssh -i ~/.ssh/win01 -o IdentitiesOnly=yes josh@10.10.50.30
```

The server accepts only the key in the `incus/windows` `ssh_authorized_key`
variable; password and keyboard-interactive logins are disabled. To rotate
the key, write the new public key to
`C:\ProgramData\ssh\administrators_authorized_keys` and update the variable
so a rebuilt VM gets it.

## Agent desktop control

[Windows-MCP](https://github.com/CursorTouch/Windows-MCP) 0.8.8 gives MCP
agents screenshots, the UI tree, input, and PowerShell on `win01`. It runs in
`josh`'s interactive session as the `windows-mcp-server` logon task, under a
headless console host, and serves streamable HTTP on port 8000. The
first-logon script sets all of this up.

| Item | Value |
| --- | --- |
| Install | `uv tool install --python 3.14 windows-mcp==0.8.8` (newer Pythons lack a PyYAML wheel and fail without a compiler) |
| Config | `C:\Users\josh\.windows-mcp\config.toml`, UTF-8 without BOM (a BOM fails with `Invalid statement (at line 1, column 1)`) |
| Auth | Bearer token `win01.windows_mcp_auth_key` in `services/windows/win01.sops.yaml` |
| Access | `ip_allowlist` and the `win01-windows-mcp` firewall rule: `10.10.0.0/16`, `192.168.1.0/24`, `192.168.2.0/24`, `100.64.0.0/10` |
| Telemetry | Off: user environment `ANONYMIZED_TELEMETRY=false` |
| Logs | `C:\Users\josh\.windows-mcp\server.log` and `server.error.log` |
| Sign-in | Sysinternals Autologon signs `josh` in at boot; the password is an LSA secret, not a registry value |
| RDP disconnect | Task `win01-rdp-to-console` (SYSTEM) runs `tscon` to return the session to the console, unlocked |

The MCP client entry reads the token at connect time:

```json
"win01": {
  "type": "http",
  "url": "http://10.10.50.30:8000/mcp",
  "headers": {
    "Authorization": "!printf 'Bearer %s' \"$(AWS_PROFILE=lab-admin sops -d --extract '[\"win01\"][\"windows_mcp_auth_key\"]' ~/code/glab/secrets/services/windows/win01.sops.yaml)\""
  }
}
```

The token grants administrator-level control through the `PowerShell` and
`Registry` tools. Transport is plain HTTP: the token crosses the tailnet
(encrypted) and VLAN 50 in clear text.

UI tools need an unlocked interactive session. Autologon provides one at
every boot, and closing a Remote Desktop window returns the session to the
console instead of leaving it locked. Signing out (rather than closing the
window) ends the session; the server then stops until the next sign-in or
reboot. Restart it with `Start-ScheduledTask windows-mcp-server` over SSH.
Rotating the `josh` password requires running Autologon again with the new
password (`C:\ProgramData\win01\Autologon64.exe /accepteula josh WIN01 <password>`).

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
