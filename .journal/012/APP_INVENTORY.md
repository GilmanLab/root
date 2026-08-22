# Application inventory — MacBook vs Mac Studio

Captured 2026-08-22. macOS: MacBook **26.4**, Studio **26.6.2**.

Scan covers `/Applications` and `~/Applications` (depth 2). MacBook 66 apps, Studio 53 apps, 41 shared.


## Only on the MacBook

| App | Version |
|---|---|
| Adrafinil | 1.2.0 |
| Albion-Online | - |
| Baldur's Gate 3 | - |
| Bitburner | - |
| Buzz | 0.5.11 |
| ChatGPT | 26.810.41047 |
| CleanShot X | 4.8.8 |
| Devin | 3.0.21 |
| Google Chrome | 151.0.7922.173 |
| Grok Bot | 0.20.0 |
| Hades II | - |
| Mem | 2.16.5 |
| Monal | 6.4.15 |
| Paseo | 0.4.0 |
| Pencil | 1.1.38 |
| Raspberry Pi Imager | v2.0.0 |
| RimWorld | - |
| Sculptor | 0.2.13-rc.2 |
| Trezor Suite | 25.8.2 |
| TurboTax 2025 | 2025.r26.044 |
| UlyssesMac | 39.3 |
| Xcode | 26.2 |
| balenaEtcher | 2.1.6 |
| iTermAI | 1.1 |
| iTermBrowserPlugin | 1.0 |

## Only on the Studio

| App | Version |
|---|---|
| Antigravity | 2.0.0 |
| Camtasia 2023 | 2023.3.13 |
| Codex | 26.707.31428 |
| Elgato Camera Hub | 1.7.0 |
| Elgato Wave Link | 2.0.5 |
| Loom | 0.339.4 |
| REALFORCE Connect | 4.0.1 |
| Roblox | 0.720.0.7201168 |
| Signal | 6.32.0 |
| Snagit 2023 | 2023.2.3 |
| Snagit 2024 | 2024.2.4 |
| Wireshark | 4.6.2 |

## Shared, but different versions

| App | MacBook | Studio |
|---|---|---|
| Arc | 1.160.0 | 1.155.1 |
| Caffeine | 1.1.4 | 1.1.3 |
| Claude | 1.20186.1 | 1.1.9310 |
| CurseForge | 1.288.0-28211 | 1.298.3-31077 |
| Cursor | 3.16.17 | 3.11.13 |
| Discord | 0.0.407 | 0.0.384 |
| GarageBand | 10.4.11 | 10.4.8 |
| GeForceNOW | 2.0.87.131 | 2.0.79.166 |
| Keynote | 14.2 | 13.1 |
| Logseq | 0.10.14 | 0.10.9 |
| Multipass | 1.16.1 | - |
| Numbers | 14.2 | 13.1 |
| Ollama | 0.32.6 | 0.9.3 |
| OrbStack | 2.1.0 | 2.2.3 |
| Pages | 14.2 | 13.1 |
| Podman Desktop | 1.25.1 | 1.26.2 |
| Raycast | 1.104.25 | 1.104.19 |
| Safari | 26.4 | 26.6.2 |
| Shadow PC | 9.9.10324 | 9.9.10318 |
| Slack | 4.51.185 | 4.50.143 |
| Spark Desktop | 3.27.4 | 3.14.5 |
| Spotify | 1.2.96.518 | 1.2.97.270 |
| Syncthing | 2.1.2-1 | 2.0.14-1 |
| Telegram | 7.0.9 | 12.9 |
| VMware Fusion | 26.0.0 | 25.0.0 |
| Visual Studio Code | 1.130.0 | 1.101.2 |
| WinBox | 4.1.102000 | 4.0.98044 |
| Windows App | 11.1.5 | 11.0.5 |
| iMovie | 10.4.3 | 10.3.6 |

## Shared, same version

`1Password`, `BALL x PIT`, `BitCraft Online`, `Claude Code URL Handler`, `Escape From Duckov`, `Moonlight`, `Necesse`, `Screen Studio`, `Steam`, `Tailscale`, `iTerm`, `zoom.us`


## Homebrew casks

All 19 casks declared in `configuration.nix` are present on both machines. Undeclared extras:

| Scope | Casks |
|---|---|
| MacBook only | `ghd`, `goreleaser-pro`, `monal`, `vagrant` |
| Studio only | `element`, `hyperkey`, `microsoft-remote-desktop`, `postman`, `signal`, `snagit`, `sunsama`, `vivaldi`, `zoom` |
| Both (auto-deps) | `multipass`, `ollama-app`, `syncthing-app`, `tailscale-app` |


## 2026-08-22 — Cask removal on the Studio

Removed nine undeclared Studio-only casks at Josh's request:

`element`, `hyperkey`, `microsoft-remote-desktop`, `postman`, `signal`,
`snagit`, `sunsama`, `vivaldi`, `zoom`

Verified: `brew list --cask` on the Studio is now exactly the 19 casks declared
in `configuration.nix` plus the four auto-dependencies (`multipass`,
`ollama-app`, `syncthing-app`, `tailscale-app`), and none of the nine apps
remain in `/Applications`. `microsoft-remote-desktop` removed `Windows App.app`
(its current name), and the `snagit` uninstall also took `Snagit 2024.app`,
which was a manual install sharing TechSmith package receipts.

Studio-only applications remaining: Camtasia 2023, Elgato Camera Hub, Elgato
Wave Link, REALFORCE Connect, Roblox, Wireshark.

### Unrelated concurrent deletions

Six further apps disappeared from the Studio during the same window — Claude,
Codex, Visual Studio Code, Spark Desktop, Antigravity, Loom. These were **not**
removed by the cask uninstall: their casks are still registered and installed,
and their Caskroom staging copies date from 2023–2026-03. The unified log names
the actual requestor:

```
12:24:29 sysextd: shouldMoveAppToTrash: file:///Applications/Claude.app/
                  (requestor: /System/Library/CoreServices/Finder.app)
```

Finder, i.e. hand-deleted at the machine while the session was running.
