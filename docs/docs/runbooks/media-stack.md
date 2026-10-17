---
title: Deploy and operate the media stack
description: Deploy media01 on nas01, deliver the ProtonVPN key, wire the apps, and recover the stack.
---

# Deploy and Operate the Media Stack

`media01` runs Jellyfin, Sonarr, Radarr, Gamarr, Prowlarr, FlareSolverr,
qBittorrent, and SABnzbd under Docker Compose on `nas01`. qBittorrent shares
gluetun's network namespace, so its only egress is the ProtonVPN WireGuard
tunnel. SABnzbd uses the clear net: Usenet provider traffic is TLS and nothing
is uploaded. The OpenTofu root is `GilmanLab/fleet` `incus/media/`; its README
lists the resources and volumes.

| App | URL |
| --- | --- |
| Jellyfin | `http://10.10.50.20:8096` |
| Sonarr | `http://10.10.50.20:8989` |
| Radarr | `http://10.10.50.20:7878` |
| Gamarr | `http://10.10.50.20:6767` |
| Prowlarr | `http://10.10.50.20:9696` |
| qBittorrent | `http://10.10.50.20:8080` |
| SABnzbd | `http://10.10.50.20:8085` |
| Library share (SMB, read-only) | `smb://10.10.50.20/media` |
| Downloads share (SMB, read-only) | `smb://10.10.50.20/torrents` |

The address and VLAN are canonical in the
[address plan](../reference/networking/address-plan.md). Home clients reach
VLAN 50 through `gw01`; tailnet clients reach it through the gw01 subnet route.

## Preconditions

- `nas01:` Incus remote with the operator client certificate. The OpenTofu
  provider on macOS needs
  `INCUS_CONF="$HOME/Library/Application Support/incus"`.
- `AWS_PROFILE=lab-admin` with a live SSO session (state backend and SOPS).
- The `bulk` pool and `nas01` `fast50` interface converged by
  `fleet-cluster storage` and `fleet-cluster network`
  ([ADR-0007](../decisions/0007-expose-nas01-hdds-as-a-clustered-bulk-pool.md),
  [ADR-0008](../decisions/0008-give-service-vms-a-dedicated-services-vlan.md)).
- VLAN 50 on `sw-core01` port 7 and `gw01` `eth1.50` (`GilmanLab/networking`).
- A ProtonVPN Plus (or higher) subscription.

## Safety impact

Creating the VM touches only `nas01`. The `media` and `media01-appdata`
volumes have `prevent_destroy`; a `tofu destroy` of the root fails rather than
deleting the library or app settings. Never attach the VM to `fast40`: a
macvlan there breaks `nas01`'s OVN gateway.

## Create the ProtonVPN secret

1. In the Proton dashboard, open **Downloads → WireGuard configuration**.
   Choose platform **Linux**, turn on **NAT-PMP (Port Forwarding)**, pick a
   **P2P** server, and download the file.
2. Copy the `PrivateKey` value from the file, then create the secret in the
   `GilmanLab/secrets` checkout:

   ```bash
   mkdir -p services/media
   AWS_PROFILE=lab-admin sops edit services/media/vpn.sops.yaml
   ```

   ```yaml
   protonvpn:
     wireguard_private_key: <PrivateKey>
     server_countries: Switzerland   # optional, comma-separated
   ```

3. Commit it through a pull request like every other secret.

## Deploy

From `GilmanLab/fleet` `incus/media/`:

```bash
export AWS_PROFILE=lab-admin GLAB_AWS_STATE_BUCKET=glab-lab-tfstate-186067932323
export INCUS_CONF="$HOME/Library/Application Support/incus"
just init
just plan     # expect the VM and, on first deploy, both volumes
just apply
incus exec nas01:media01 -- cloud-init status --wait
just deliver-vpn ~/code/glab/secrets/services/media/vpn.sops.yaml
just deliver-smb ~/code/glab/secrets/services/media/smb.sops.yaml
```

The stack stays down until `deliver-vpn` installs `/etc/media/vpn.env`.
Docker waits for `/data` and `/srv/appdata` to be mounted before it starts
any container.

## Copy files from the SMB shares

Two shares, both read-only for the `media` account:

| Share | Path | Contents |
| --- | --- | --- |
| `media` | `/data/media` | The imported library: `games`, `movies`, `tv` |
| `torrents` | `/data/torrents` | qBittorrent downloads, including releases no app imported. Read-only so nothing can alter a file that is still seeding. |

The password is in `GilmanLab/secrets` `services/media/smb.sops.yaml`; copy it
to the clipboard with:

```bash
AWS_PROFILE=lab-admin sops decrypt --extract '["smb"]["password"]' \
  ~/code/glab/secrets/services/media/smb.sops.yaml | pbcopy
```

In Finder, **Go → Connect to Server** (`⌘K`), enter `smb://10.10.50.20/media`
or `smb://10.10.50.20/torrents`,
choose **Registered User**, name `media`, paste the password, and save it in
the keychain. To change the password, edit the secret and rerun
`just deliver-smb`.

## Wire the apps

The first login on each app creates its admin account. qBittorrent prints a
temporary admin password once, in its log:

```bash
incus exec nas01:media01 -- docker logs qbittorrent 2>&1 | grep -i password
```

Change it in **Tools → Options → Web UI**. Leave **Bypass authentication for
clients on localhost** on; gluetun uses it to push the forwarded port.

All containers see the library volume at `/data`:

| Path | Purpose |
| --- | --- |
| `/data/torrents/{tv,movies,games}` | qBittorrent category save paths |
| `/data/torrents/incomplete` | qBittorrent incomplete downloads |
| `/data/usenet/incomplete`, `/data/usenet/complete/<category>` | SABnzbd downloads |
| `/data/media/{tv,movies,games}` | Sonarr, Radarr, and Gamarr root folders; Jellyfin TV and movie libraries (read-only) |

1. Sonarr and Radarr: **Settings → Media Management**, add root folder
   `/data/media/tv` or `/data/media/movies`. Leave **Use Hardlinks instead of
   Copy** on.
2. Sonarr and Radarr: **Settings → Download Clients → qBittorrent**, host
   `gluetun`, port `8080`, category `tv` or `movies`.
3. qBittorrent: create categories `tv` → `/data/torrents/tv` and `movies` →
   `/data/torrents/movies`.
4. Prowlarr: **Settings → Apps**, add Sonarr (`http://sonarr:8989`) and Radarr
   (`http://radarr:7878`) with their API keys and Prowlarr server
   `http://prowlarr:9696`. Add indexers in Prowlarr only; it syncs them.
5. Prowlarr: **Settings → Indexers → + → FlareSolverr**, host
   `http://flaresolverr:8191/`, tag `flaresolverr`. Add that tag to every
   indexer that reports "blocked by CloudFlare Protection"; untagged indexers
   never use FlareSolverr.
6. Jellyfin: add libraries on `/data/media/tv` and `/data/media/movies`, then
   restart it (`docker restart jellyfin`). Jellyfin starts watching library
   folders only at startup, and the first scan skips an empty folder, so
   imports into a library created after startup do not appear until a scan.
7. Gamarr: root folder `/data/media/games`; **Settings → Download Clients →
   qBittorrent**, host `gluetun`, port `8080`, category `games` (qBittorrent
   category `games` → `/data/torrents/games`). Prowlarr has no Gamarr app
   type, so `gamarr-indexer-sync.timer` on `media01` mirrors every enabled
   Prowlarr indexer with console (1xxx) or PC (4xxx) categories into Gamarr
   hourly, as Torznab/Newznab entries named `<indexer> (Prowlarr)`. Add
   indexers in Prowlarr only. To sync immediately or preview, run
   `just sync-gamarr-indexers` (`--dry-run`) from `GilmanLab/fleet`
   `incus/media/`. The job leaves non-Prowlarr entries alone and keeps the
   toggles, priority, and seed settings you change on its entries.
8. SABnzbd: complete the setup wizard with the Usenet provider's server,
   port `563`, SSL on, and its credentials. Download paths are seeded. In
   **Config → Categories**, set the folder of `tv` and `movies` to their own
   names and add `games` with folder `games`; empty folders put every job
   directly in `/data/usenet/complete`.
9. Sonarr, Radarr, and Gamarr: **Settings → Download Clients → + → SABnzbd**,
   host `sabnzbd`, port `8080`, the API key from **SABnzbd → Config →
   General**, category `tv`, `movies`, or `games`. Prefer Usenet in
   **Settings → Profiles → Delay Profiles**, protocol **Prefer Usenet**.
10. Prowlarr: **Indexers → Add Indexer**, add NZBgeek and NZBFinder with the
    API key from each site's account page. Do not tag them `flaresolverr`.
    Prowlarr syncs them to Sonarr and Radarr. Add NZBgeek to Gamarr as Newznab
    the same way step 7 adds Torznab indexers. NZBFinder has no Console (1000)
    or PC (4000) categories, so Gamarr rejects it.

## Verify

```bash
# VPN egress: must be a Proton address, never the home WAN address.
incus exec nas01:media01 -- docker exec gluetun wget -qO- https://ipinfo.io/ip
# Forwarded port gluetun negotiated and pushed into qBittorrent.
incus exec nas01:media01 -- docker logs gluetun 2>&1 | grep -i 'port forwarded'
# Kill switch: with gluetun stopped, qBittorrent has no network at all.
incus exec nas01:media01 -- docker stop gluetun
incus exec nas01:media01 -- docker exec qbittorrent curl -s -m5 https://ipinfo.io/ip  # must fail
incus exec nas01:media01 -- docker compose --project-directory /opt/media up -d
```

## Change the stack

Cloud-init writes `/opt/media/compose.yaml` only on first boot. To add a
service or bump an image without rebuilding the VM, edit `images` or
`templates/compose.yaml.tftpl`, then:

```bash
just plan     # expect an in-place update of cloud-init.user-data only
just apply
just sync-compose
```

`sync-compose` pushes the applied compose file and runs
`docker compose up -d --remove-orphans`; only changed containers restart.

## Recovery

- **Rebuild the VM:** `tofu apply -replace=incus_instance.media`, wait for
  cloud-init, then `just deliver-vpn`. Both volumes and every app setting
  survive. If the pinned image has expired from `images:`, pin a current
  `images:ubuntu/26.04/cloud` VM fingerprint in `variables.tf` first.
- **Rotate the VPN key:** edit the secret, then rerun `just deliver-vpn`; it
  recreates gluetun and qBittorrent.
- **Stack down after a reboot:** check `systemctl status docker` in the VM.
  A failed `ExecStartPre` means a volume did not mount; inspect
  `incus config device show nas01:media01`.
- **qBittorrent "File error alert ... file_mmap ... No such device":** the
  Disk IO type was reset to memory-mapped files, which virtiofs rejects. Set it
  back to POSIX, restart qBittorrent, then resume the errored torrents:

  ```bash
  incus exec nas01:media01 -- docker exec qbittorrent curl -s \
    --data 'json={"disk_io_type":2}' http://127.0.0.1:8080/api/v2/app/setPreferences
  incus exec nas01:media01 -- docker restart qbittorrent
  ```

## Hardware transcoding

`gpu_pci_address` can pass the Radeon 890M (`0000:c7:00.0`) through for
VA-API. On 2026-10-16 a test VM bound `amdgpu` to it, but PSP firmware init
failed (`PSP tmr init failed`) with the factory BIOS (2 GiB UMA, VBIOS
`113-STRIXEMU-001` from the ROM BAR). The likely fix is setting
`UMA_SPECIFIED` to 8 GiB and enabling ReBAR in the `nas01` BIOS, which needs a
`nas01` reboot. Until that is verified on a throwaway VM, Jellyfin transcodes in
software.

## Escalate

- gluetun reports no forwarded port: the Proton key was generated without
  NAT-PMP, or the server is not P2P. Regenerate the key.
- `incus storage info nas01:bulk --target nas01` shows the pool degraded:
  follow the `hdd` pool recovery notes in
  [Rebuild nas01](rebuild-nas01.md).
