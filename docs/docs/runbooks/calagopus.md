---
title: Deploy and operate Calagopus
description: Deploy calagopus01 on lab01, finish the first-run wizard, install panel extensions, create modded Minecraft servers, and recover the VM.
---

# Deploy and Operate Calagopus

`calagopus01` runs [Calagopus](https://calagopus.com), a Rust game server
panel, for modded Minecraft. The upstream heavy All-in-One image puts the Panel
and its integrated Wings in one container. Wings starts each game server as a
sibling Docker container. The VM is on `lab01` at the services VLAN address in
the [address plan](../reference/networking/address-plan.md). The OpenTofu root
is `GilmanLab/fleet` `incus/calagopus/`; its README lists the volumes, mounts,
and image pins.

| Access | Value |
| --- | --- |
| Panel | `http://10.10.50.40:8000` |
| SFTP | `10.10.50.40:2022`, panel username and password |
| Game servers | `10.10.50.40:25565`–`25600` (panel allocations) |
| Administrator | `admin.username` / `admin.password` in `GilmanLab/secrets` `services/calagopus/panel.sops.yaml` |

## Preconditions

- `nas01:` Incus remote with the operator client certificate. The OpenTofu
  provider on macOS needs
  `INCUS_CONF="$HOME/Library/Application Support/incus"`.
- `AWS_PROFILE=lab-admin` with a live SSO session (state backend and SOPS).
- VLAN 50 tagged on `sw-core01` `bond-lab01` (`GilmanLab/networking`) and
  `lab01` `fast50` converged by `fleet-cluster network`. `lab01` must run an
  IncusOS release from 2026-09-17 or later: earlier releases reject LACP bond
  members during network validation
  ([lxc/incus-os@8accfe0](https://github.com/lxc/incus-os/commit/8accfe0f99)).
- The `.c7s.zip` for every extension to install. ric-rac's Minecraft Modpack
  Installer ships it inside the purchased bundle at
  `calagopus/org_ricrac_modpackinstaller.c7s.zip`; ignore the bundle's
  Pterodactyl `upload/` tree and `wings.patch`.

## Safety impact

Creating the VM touches only `lab01`. The data volume has `prevent_destroy`.
The panel holds the host Docker socket, which is root on the VM; keep it on the
services VLAN and off the internet. `panel.encryption_key` encrypts secrets in
the panel database: never change or regenerate it after the first start, or the
panel cannot read its own stored secrets. Never attach the VM to `fast40`: a
macvlan there breaks `lab01`'s OVN gateway.

## Deploy

From `GilmanLab/fleet` `incus/calagopus/`:

```bash
export AWS_PROFILE=lab-admin GLAB_AWS_STATE_BUCKET=glab-lab-tfstate-186067932323
export INCUS_CONF="$HOME/Library/Application Support/incus"
just init
just plan     # expect the VM and, on first deploy, the data volume
just apply
incus exec nas01:calagopus01 -- cloud-init status --wait
just deliver-secrets ~/code/glab/secrets/services/calagopus/panel.sops.yaml
```

If `just apply` fails with `The requested image couldn't be found`, the pinned
`images:` fingerprint has expired. Pin the current
`images:ubuntu/26.04/cloud` VM fingerprint in `variables.tf` and plan again.

`deliver-secrets` writes `/etc/calagopus/panel.env` and starts the stack. The
panel answers on port 8000 within about a minute.

## Finish the first-run wizard

Open `http://10.10.50.40:8000` and complete the wizard:

1. **Register**: the administrator from `panel.sops.yaml`.
2. **Configuration**: keep Application URL `http://10.10.50.40:8000` and
   registration off. Login cookies and the console connection derive from this
   URL; a mismatch breaks both.
3. **Egg Repositories**: import **Pterodactyl Game Eggs**.
4. **Location**: keep the integrated location and the **Local** backup disk.
5. **Node**: name `lab01`, SFTP host `10.10.50.40`, memory 14 GiB, disk
   220 GiB, allocation IP `10.10.50.40` with ports `25565-25600`. The
   integrated Wings is already paired; the next step verifies it.
6. **Server**: skip.

## Install an extension

```bash
just install-extension /path/to/<package>.c7s.zip
```

The recipe stores the archive under its underscored package identifier in
`/srv/calagopus/panel/build/extensions/` and restarts the panel, which compiles
and loads it. **Admin → Extensions** shows the extension and **View build
logs** streams the build. A build failure that names an extension usually means
it does not support the current panel version; see the upstream
[troubleshooting table](https://calagopus.com/docs/panel/extensions/installing-extensions#troubleshooting).

## Create a modded Minecraft server

1. **Admin → Servers → Create**. Install the **Forge Enhanced** egg from the
   repository if it is missing. Its startup command reads `unix_args.txt`,
   which modpack installs provide for Forge and NeoForge packs.
2. Set the node `lab01`, owner, memory (8–10 GiB for large packs), disk, and a
   free primary allocation. The Docker image may stay at `java 21`.
3. Open the server in the client area, then **Modpacks**. Pick the provider
   (CurseForge, Modrinth, FTB, ATLauncher, Technic, VoidsWrath), choose a pack
   and version, and **Install**. Enable **delete all files** only for a fresh
   server or a deliberate pack change; it wipes the world too.
4. The install runs as a reinstall in ric-rac's installer image. Afterwards the
   extension switches the server's Docker image to the Java version the pack
   needs. Start the server from the console.
5. The first start stops at the Minecraft EULA prompt. Type `true` in the
   console to accept it; the server writes `eula.txt` and continues.

On 2026-11-06, All the Mods 10 (8.5, NeoForge 21.1.265, 468 mods) installed
from CurseForge in under a minute and reached `Done` 9.4 s after the EULA was
accepted, using about 8 GiB of a 10 GiB limit.

CurseForge works without configuration: the extension ships a CFCore API key.
Replace it under **Admin → Extensions → Configure** if CurseForge requests
start failing.

## Verify

- `curl -s -o /dev/null -w '%{http_code}\n' http://10.10.50.40:8000/` returns
  `200`.
- **Admin → Nodes → lab01** shows the node online.
- A server's console streams output in the browser, and a Minecraft client
  connects to its allocation.

## Day-2 operations

- **Logs**: `just logs` follows the panel and integrated Wings.
- **Compose changes**: edit the template, `just plan`/`just apply`, then
  `just sync-compose`. Cloud-init writes the compose file only on first boot.
- **Panel upgrades**: bump `images.panel` to the next `<version>-heavy-aio`
  tag, apply, and `just sync-compose`. Installed extensions recompile against
  the new version; read the Calagopus release notes first.
- **Backups**: server backups land in `/var/lib/calagopus-wings/backups` on the
  data volume. They do not leave `lab01`.

## Recovery

- **Rebuild the VM**: `tofu apply -replace=incus_instance.calagopus`, wait for
  cloud-init, then `just deliver-secrets`. The data volume keeps the panel
  database, extensions, servers, and backups; bootstrap finds the filesystem by
  label and does not reformat it.
- **Panel will not start after an extension change**: stop the stack, delete
  that archive from `/srv/calagopus/panel/build/extensions`, remove
  `/srv/calagopus/panel/build/binaries`, and start the stack again.
- **Panel cannot decrypt stored secrets**: the encryption key changed.
  Re-deliver the original key from `panel.sops.yaml`; do not generate a new
  one.

## Escalation

Stop and investigate before continuing when `lab01` cannot converge `fast50`,
the data volume is missing or unmounted (`docker.service` refuses to start
without it), or a panel upgrade reports database migration errors.
