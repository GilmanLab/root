---
id: 012
title: Make the MacBook and Mac Studio interchangeable work environments
started: 2026-08-22
---

## 2026-08-22 11:24 — Kickoff

Goal for the session: make Josh's MacBook and Mac Studio interchangeable work
environments, so either machine can pick up work with the same tooling,
configuration, and state. The lab is a candidate utility for achieving that
(e.g. shared services, storage, remote compute), not a mandated component.

Current state of the world:

- Lab v2 substrate is largely up: four-node Incus cluster (nas01 + lab01–03),
  encrypted `data` pools on every node plus nas01's 17.4TB `hdd` raidz1, VLAN 30
  storage network converged but with a lab-side datapath blocker (T48, awaiting
  10G DACs ~2026-08-24 and the merged IncusOS ice-firmware fix).
- Networking (gw01/VyOS, sw-core01/RouterOS+OpenTofu, sw-mgmt01) is under
  management; secrets root of trust is SOPS + KMS + YubiKey in
  `GilmanLab/secrets`; Tailscale policy is GitOps-managed in
  `GilmanLab/networking`.
- No existing workstation/dotfiles automation is recorded in TECH_NOTES.md —
  workstation parity appears to be greenfield for Lab v2.
- Open threads carried in: T44 (Operations Center spike), T45 (PiKVM default
  creds), T46 (secrets checkout path `~/code/glab/secrets`), T47
  (meshcommander disposition), T48 (lab fast-path), T49 (upstream pyinfra-incus
  ops), plus T16 object storage.

Plan (agile, prototype-first): inventory what actually differs between the two
Macs and what "interchangeable" must cover (tooling, dotfiles, secrets, dev
state, data, running services), pick the smallest thing that proves the model,
build it, then decide whether the lab hosts anything durable. Avoid designing a
full workstation-management architecture up front.


## 2026-08-22 11:40 — Remote access to the Mac Studio: findings

Asked: how to easily SSH into the Mac Studio. Investigated from the MacBook
(`jmgilman-mbp`, LAN 192.168.1.20).

Facts gathered:

- Studio is on the tailnet as `studio-1.tailda715.ts.net` / `100.122.142.76`
  (node `nbrRP6QY3S11CNTRL`, key expiry 2026-09-30); MagicDNS resolves it. On
  the home LAN it is `192.168.1.10`, MAC `a4:fc:14:35:fc:13`.
- It was asleep and offline on the tailnet. A *broadcast* WoL magic packet did
  nothing; a *unicast* magic packet to `192.168.1.10:9` brought it to dark wake
  (ICMP replies) but not to full wake — Tailscale stayed offline and every
  probed TCP port (22, 5900, 3283, 88, 445) stayed closed.
- No sshd on the Studio (Remote Login off) and none on the MacBook either
  (`com.openssh.sshd` not loaded in the system domain).
- Tailnet policy (`GilmanLab/networking/tailscale/policy.hujson`) already allows
  admin → everything, and Tailscale SSH `check` for member → `autogroup:self`.
  No policy change is needed for plain SSH over the tailnet. Tailscale SSH's
  *server* side is not available on macOS with the GUI cask (requires the
  open-source `tailscaled` CLI variant) — Tailscale is installed here as a
  Homebrew cask, so plain sshd over Tailscale is the right transport.

Big discovery for the session's actual goal: **both Macs are already declarative
nix-darwin hosts.** Live flake is `~/.local/nix` (github.com/jmgilman/nix),
with `darwinConfigurations.jmgilman-mbp` and `darwinConfigurations.studio`
sharing `configuration.nix` plus `home/` (home-manager), differentiated by a
`machines.<host>` attrset (`hostname`, `sshKeyName`, `mfaDevice`). Rebuild
command in use: `sudo darwin-rebuild switch --flake ~/.local/nix`. The repo has
uncommitted changes (flake.nix, flake.lock, home/{packages,programs,shell}.nix)
and an untracked `result` symlink. Stale repos `~/code/mac` (2023) and
`~/code/nixos` are not the live config.

Consequences:

- `~/.ssh/config` is a read-only home-manager symlink into the Nix store; SSH
  host entries must be edited in `home/ssh.nix`, not by hand.
- nix-darwin exposes exactly the knobs needed: `services.openssh.enable`
  (bootstraps `com.openssh.sshd` via launchctl, deliberately avoiding the
  Full Disk Access requirement of `systemsetup -setremotelogin`),
  `power.sleep.computer`, and `power.restartAfterPowerFailure`.
- Defects noticed in `home/ssh.nix`: lab01–03 point at the dead v1 addresses
  `10.10.10.203–205` (actual: `.11`/`.12`/`.13`), and the studio's
  `sshKeyName` is `id_ed25519_studio` while the key file present on the
  MacBook is `id_ed25519_studo` (typo).

Proposed shape (pending Josh): keep sshd + never-sleep declarative in
`~/.local/nix`, address hosts by MagicDNS name so LAN and remote behave the
same, and manage `authorized_keys` for both machines from home-manager so the
two hosts trust each other symmetrically. One physical touch at the Studio is
unavoidable for the first rebuild.

## 2026-08-22 11:55 — Studio back from its OS upgrade; nix changes written

Correction to the previous entry: the Studio was mid-OS-upgrade, not
misconfigured. Now that it is booted and logged in, `sshd` **is** listening
(22 and 5900 open from the MacBook, tailnet shows it online). The earlier
all-ports-closed reading was dark wake, not disabled sharing.

Remaining gap is authorization only: every local key
(`id_ed25519_macbook`, `id_ed25519_studo`, `id_ed25519_claude`, `id_rsa`,
`id_ed25519_rk`) gets `Permission denied (publickey,password,
keyboard-interactive)`, so no MacBook key is in the Studio's
`authorized_keys` and password auth is still enabled.

Changes written in `~/.local/nix` (not committed — Josh's WIP is in the same
tree):

- `configuration.nix`: `services.openssh.enable = true;` for both hosts.
- `flake.nix`: Studio module gains `power.sleep.computer = "never"` and
  `power.restartAfterPowerFailure = true` so it stops falling off the tailnet.
- `home/ssh.nix`: `studio` → `studio-1.tailda715.ts.net` and `macbook` →
  `macbook-pro.tailda715.ts.net`, both with the host's own key.

Verified: `nix build .#darwinConfigurations.{studio,jmgilman-mbp}.system` both
succeed, and the generated `hm_.sshconfig` contains the two new host blocks.
Not yet applied — `darwin-rebuild switch` needs sudo and there is no
`pam_tid` line in `/etc/pam.d/sudo_local`, so sudo is password-only, including
over SSH.

Open question raised with Josh: whether to allow passwordless sudo for `josh`
on both machines. Without it, no agent can converge either machine over SSH
unattended; with it, any process running as `josh` can escalate. Also pending:
whether to commit/push the `~/.local/nix` changes (his WIP — bun overlay,
package churn, mise activation — sits in the same working tree, and `master`
has no upstream tracking configured).

## 2026-08-22 12:20 — SSH working; config committed and pushed

Josh installed the MacBook key on the Studio, so `ssh josh@studio-1.tailda715.ts.net`
works from the MacBook now. Studio facts from the first remote survey:
macOS 26.6.2, hostname `studio`, Determinate Nix 3.13.1 (newer than the
MacBook's 3.4.1), running `darwin-system-26.05` (the MacBook is on 26.11), and
`~/.local/nix` was two commits behind with a local one-line edit.

`pmset -g` on the Studio explains the disappearances outright:
`sleep 1` — a **one-minute** idle sleep (currently held off by a powerd
assertion), `autorestart 0`, `womp 1`.

Committed and pushed to `github.com:jmgilman/nix` in three commits, WIP kept
separate as Josh asked (flake.nix carried both his and my hunks, so I reverted
my block, committed his, then restored mine):

- `ae8f37b chore:` his WIP — bun 1.3.14 overlay, package churn, mise in zsh,
  home-manager `backupFileExtension`.
- `09ac18c feat(remote):` sshd on both hosts, `studio`/`macbook` MagicDNS host
  entries, Studio never-sleep + restart-after-power-failure, passwordless sudo
  for `josh`.
- `1efc112 fix(studio):` `mfaDevice = "studio-yubikey"`, the Studio's local
  uncommitted fix, now upstream.

`master` had no upstream tracking on the MacBook; `git push -u` fixed that.

New friction found — **the Studio cannot talk to GitHub headlessly**. Its
`id_ed25519_studio` (SHA256:KAV0p/+Kfetb0AcQY+WPHSAa5SIIASMQNGmje/Z/lWM, the
same key the MacBook stores as the misnamed `id_ed25519_studo`) is rejected by
GitHub, and non-interactive SSH sessions have no agent. Worked around with
`ssh -A` agent forwarding to pull. Two real fixes needed: register the Studio's
key on GitHub (my `gh` token lacks `admin:public_key`; `gh auth refresh -h
github.com -s admin:public_key` is interactive), and add a `github.com`
matchBlock to `home/ssh.nix` — the existing `github` alias only applies to
remotes written as `git@github:`, not the real `git@github.com:` remotes.

`nix build .#darwinConfigurations.studio.system` succeeds **on the Studio**, so
the switch is pre-warmed. Both machines now need one attended
`sudo darwin-rebuild switch` to install passwordless sudo; after that, agent
convergence is unattended in both directions.

## 2026-08-22 12:45 — Both machines converged; one self-inflicted lockout

Josh ran both attended switches. Verified: passwordless sudo works on both,
both run `darwin-system-26.11.15abb8c`, MacBook `sshd` is loaded, and the
Studio now reports `sleep 0` with `autorestart 1` — the one-minute sleep is
gone.

Then made trust symmetric and pushed `b7a36b5`: each Mac carries both public
keys in `authorized_keys`, and the GitHub identity is bound to the `github.com`
hostname. Applied it to the MacBook unattended, then to the Studio unattended
over SSH (`git pull` still needed `ssh -A`).

**That broke public-key auth on both machines and locked me out of the
Studio.** Root cause: I wrote `authorized_keys` with `home.file`, which is a
symlink into `/nix/store`, and the store directory is group-writable
(`drwxrwxr-t root:nixbld`), so sshd's `StrictModes yes` refuses the file. No
log line says so — the connection just falls through to
`Permission denied (publickey,...)`.

Fix in `f57fde7`: keep the key list in `pkgs.writeText`, then a home-manager
activation entry (`entryAfter ["writeBoundary"]`) removes any stale symlink and
`install -m 600` copies the content into `$HOME/.ssh/authorized_keys` as a real
user-owned file. Applied on the MacBook and proven by loopback SSH with the
MacBook key. The Studio still carries the broken symlink, so it needs one local
command from Josh to restore ingress before I can converge it remotely.

Two incidental facts worth keeping:

- `~/.ssh/id_ed25519_studo` on the MacBook is **passphrase-protected**, so it
  can never authenticate in a `BatchMode` agentless session. My earlier
  "every key is rejected" reading over-attributed the failure to the server.
- The Studio has no working GitHub credential at all: `id_ed25519_studio`,
  `id_ed25519_devos`, `id_ed25519_bootstrap` and `vyos-gateway` are all
  rejected by GitHub, there is no 1Password SSH agent, and its `gh` token is
  invalid. Adding the key to the local agent fixes interactive sessions only.

Lesson for anything declarative touching sshd on a Nix machine: files sshd
validates under `StrictModes` (`authorized_keys`, host keys) must be copied
out of the store, never symlinked into it.

## 2026-08-22 13:05 — Both machines converged and symmetric

Josh restored ingress on the Studio. Converged it remotely to `f57fde7`, then
to `499e368`; both Macs now write `~/.ssh/authorized_keys` as a real 600 file
containing both workstation keys, and MacBook→Studio SSH works unattended.

One more self-inflicted break, found and fixed in the same pass: the
`github.com` matchBlock had `identitiesOnly = true`, which also suppresses keys
offered by a **forwarded** agent — that is what killed `ssh -A`-based pulls on
the Studio immediately after the previous switch. Dropped it (`499e368`);
`git ls-remote` over a forwarded agent works again.

Remaining gap, and it is the same root cause for two symptoms: **the Studio's
`id_ed25519_studio` is passphrase-protected**, exactly like the MacBook's copy.
So headless Studio→MacBook SSH fails and headless Studio→GitHub fails, while
the MacBook's `id_ed25519_macbook` (no passphrase) works for both. Until this
is resolved, the Studio can be driven but cannot drive.

Options put to Josh: strip the passphrase from the existing Studio key (keeps
every existing authorization on dev/nas/jumpbox/k0s intact, one `ssh-keygen -p`
he must run because it needs the passphrase), or mint a separate
passphrase-less automation key (I can do it unattended, but it adds a second
key per machine and needs registering wherever the Studio must reach).

## 2026-08-22 13:25 — Correction: it was never the passphrases

Josh pushed back on my claim that the MacBook's key has no passphrase. He was
right: `id_ed25519_macbook` is `aes256-ctr` encrypted, same as the Studio's
key. My loopback test "proved" otherwise only because ssh silently used the
**agent's** unlocked copy despite `-i`, so the test never touched the file.

That single bad inference had produced two wrong conclusions, both now
retracted:

- "The Studio's key is not registered on GitHub." It is. Every earlier
  agentless `-i ~/.ssh/id_ed25519_studio -o IdentitiesOnly=yes` probe failed
  because BatchMode cannot prompt for the passphrase, not because GitHub
  refused the key.
- "Strip the passphrase / mint an automation key." Neither is needed.

Actual root cause: **macOS rotates the per-user ssh-agent socket path on every
login (`/var/run/com.apple.launchd.<random>/Listeners`) and an inbound SSH
session never inherits `SSH_AUTH_SOCK`.** Both machines' launchd agents already
hold their unlocked keys (MacBook `zBsbRxkw…`, Studio `KAV0p/+K…`); a machine
reached over SSH simply had no way to find its own agent.

Fix (`a1667cd`): a home-manager launchd login agent publishes a stable symlink
`~/.ssh/agent.sock` → the live socket, and `Host *` sets
`IdentityAgent ~/.ssh/agent.sock`. Darwin-only; the Linux home configuration is
untouched.

Verified after converging both machines, with no agent forwarding anywhere:

- MacBook → Studio with `SSH_AUTH_SOCK` unset: works.
- Studio → MacBook: works (`REVERSE_OK`).
- Studio → GitHub: `Hi jmgilman!`, and `git ls-remote` succeeds.
- Studio → MacBook `sudo -n`: works, so either machine can now converge the
  other unattended.

Both Macs are now genuinely symmetric for remote access. `ssh -A` is no longer
needed for anything.

## 2026-08-22 13:45 — Homebrew handed over to Nix

Applied `dd93c7d` to both machines. `homebrew.onActivation.cleanup = "uninstall"`
is live, so Nix is now authoritative: undeclared casks and formulae are removed
on every activation instead of accumulating.

Moved to `home/packages.nix` (16): age, bitwarden-cli, cilium-cli, container,
flyctl, helmfile, hubble, iperf3, k3d, lima, mise, qemu, shellcheck, skopeo,
tree, worktrunk. Already there and now de-duplicated from Homebrew: ripgrep,
sops, kubernetes-helm; plus gnupg (systemPackages) and direnv
(`programs.direnv`).

Kept on Homebrew deliberately, with the reason recorded inline in
`configuration.nix`: ansible (nixpkgs ships `ansible-core` without the
community collections — Josh's call), ffmpeg (nixpkgs 8.1 vs 9.0), pandoc
(3.7 vs 3.10), pinentry-mac (1.1 vs 1.3), incus (**nixpkgs marks it
linux-only and there is no darwin client — Homebrew is the only source**),
and the version managers (goenv/nodenv/pyenv/pipx/poetry/rustup/cdktf/dagger/
mockery).

Casks dropped: claude, logseq, readdle-spark, visual-studio-code.

Result — MacBook formulae 150 → 76, Studio → 73; casks on both are exactly the
15 declared plus three cask-level auto-deps (`ollama-app`, `syncthing-app`,
`tailscale-app`).

Verified on both machines: `wt`, `mise`, `sops`, `age`, `rg`, `helm`, `skopeo`,
`lima`, `qemu-img` resolve to `~/.nix-profile/bin`; `gpg` to
`/run/current-system/sw/bin`; `incus`, `ansible`, `pandoc`, `tree` to
`/opt/homebrew/bin`.

Three findings worth keeping:

- **`go` was never a manual install.** `brew uses --installed go` returns only
  `golangci-lint`, whose sole dependency is `go`. Homebrew retains dependencies
  of declared packages, so declaring `golangci-lint` would keep `go` for free.
  Neither is declared, so both were removed; `goenv` is unaffected because it
  builds its own toolchains under `~/.goenv`.
- **`tree` survives from Homebrew on both machines** even though Nix provides
  it — it is a dependency of `ansible`, which we kept. Harmless, but it means
  `/opt/homebrew/bin/tree` shadows nothing: the Nix profile resolves first.
- **The Studio's first activation failed**: `brew bundle` could not link
  `python@3.14` because the cleanup pass removed it in the same run that
  `ansible` needed it back. `brew link --overwrite python@3.14` plus a second
  `darwin-rebuild switch` converged cleanly. Expect this class of ordering
  failure whenever cleanup and install touch the same dependency.

**`wt` jumped 0.37.1 → 0.71.0** (34 releases). `wt list --format=json` still
works and its JSON is still clean on stdout, but 0.71 prints a schema warning
to stderr: *"JSON output is schema 1; a future release switches the default to
schema 2"*. The `worktrunk` skill is documented as verified against 0.37.1 and
now needs re-grounding; the json-schema pin (`[list] json-schema = 1`) is the
decision to make before schema 2 lands.

Unrelated observation while testing: the MacBook's `incus` has no `nas01`
remote configured — only `local` and a stale `incusos-spike`
(`172.16.140.134`). Lab CLI access from this machine is not set up.


## 2026-08-22 14:20 — How Homebrew takes over a manually installed app

Answered from Homebrew's source rather than folklore
(`/opt/homebrew/Library/Homebrew/cask/artifact/moved.rb`,
`/opt/homebrew/Library/Homebrew/bundle/cask.rb`).

For `app`-artifact casks, when the target path already exists:

- Plain `brew install --cask X` → hard error, install aborts:
  *"It seems there is already an App at '/Applications/X.app'."*
- `--force` → warns *"overwriting"*, trashes the existing bundle, moves the
  downloaded one in.
- `--adopt` → adopts the existing bundle in place, but only if it is identical:
  Homebrew compares `CFBundleShortVersionString` **and** `CFBundleVersion` from
  the staged download's `Info.plist` against the installed app's. Any mismatch
  raises *"It seems the existing App is different from the one being
  installed."* If neither plist parses it falls back to `diff --recursive
  --brief`. On success the download is deleted, the app stays put, and the
  Caskroom receipt now owns it.
- **Exception:** if the cask declares `auto_updates true`, the version check is
  skipped entirely and adoption always succeeds — Homebrew assumes the app
  updates itself out from under the cask.

Critically, `brew bundle` — which is what nix-darwin activation runs — always
appends `--adopt` unless `--force` is present (`bundle/cask.rb:90`). So
declaring an already-installed app is normally a no-op takeover, not a
reinstall.

`pkg`-artifact casks (zoom, realforce, elgato-camera-hub, wireshark-app,
tailscale-app) have no `Moved` artifact at all: they run the vendor installer,
which replaces the bundle in place. No conflict is possible, and the pkgutil
receipt is what Homebrew later uninstalls.

Surveyed all 23 candidates: 13 adopt unconditionally (`auto_updates true`),
5 are pkg-based, 5 match on version today, and **only 2 would fail** — Shadow
PC (installed 9.9.10318 vs cask 9.9.10457) and WinBox (4.1.102000 vs 4.3).
Both lack `auto_updates`, so each needs either a manual update first or a
one-time `brew install --cask --force`.


## 2026-08-22 14:45 — Declared the manual apps; Shadow PC removed; WinBox forced

Prepared but **not yet activated**:

- `configuration.nix` casks 15 → 33. Added the portable apps that were manually
  installed on one or both machines: adrafinil, balenaetcher, buzz, chatgpt,
  cleanshot, google-chrome, itermai, itermbrowserplugin, moonlight,
  nvidia-geforce-now, paseo, podman-desktop, screen-studio, telegram,
  trezor-suite, winbox, wireshark-app, zoom.
- `flake.nix` studio module gains a host-local `homebrew.casks` list for desk
  hardware: elgato-camera-hub, elgato-wave-link, realforce. nix-darwin merges
  the shared and per-host lists, so the Studio renders 36 casks and the MacBook
  33.
- **Camtasia deliberately left undeclared.** The `camtasia` cask tracks 2026.2.0
  while the Studio runs 2023.3.13, and the cask is `auto_updates true`, so
  declaring it would adopt silently and any later `--force` or reinstall would
  pull a three-major-version upgrade with licensing consequences. Josh's call.
- No cask exists for TurboTax 2025, VMware Fusion, or Claude Code URL Handler,
  so those stay manual.

Shadow PC removed at Josh's request. It was Studio-only (never on the MacBook)
and a manual install, not a cask: removed `/Applications/Shadow PC.app` plus
`~/Library/Preferences/com.electron.shadow.plist`,
`~/Library/Caches/com.electron.shadow{,.ShipIt}` and
`~/Library/Logs/ShadowPCDisplay_debug.log`.

WinBox adoption tested end to end, and the predicted failure reproduced exactly:

```
==> Adopting existing App at '/Applications/WinBox.app'
Error: The bundle short version of .../Caskroom/winbox/4.3/WinBox.app is
       4.3.102000 but is 4.1.102000 for /Applications/WinBox.app!
Error: winbox: It seems the existing App is different from the one being installed.
```

`brew install --cask --force winbox` then took it over on both machines
("overwriting", remove, move) — MacBook 4.1.102000 → 4.3.102000, Studio
4.0.98044 → 4.3.102000, both now registered as cask `winbox 4.3`. The Studio's
first attempt died on `curl (56) Recv failure` from download.mikrotik.com; a
plain retry succeeded, so it was transient upstream, not a cask fault.

Shadow PC needed no force handling: it was never a cask, so nothing adopts it
and `cleanup = "uninstall"` ignores it — manual apps outside Homebrew are
invisible to the cleanup pass.


## 2026-08-22 15:20 — Cask declarations activated on both machines

Applied `8409826` then `fix(casks)`. Adoption worked exactly as the source
predicted: already-installed apps kept their existing bundles and versions
(Chrome 151.0.7922.173, ChatGPT 26.810.41047, CleanShot 4.8.8, Telegram 7.1.0
all unchanged), while missing apps were installed fresh — one on the MacBook
(wireshark-app) and seventeen on the Studio.

Final state, and the two machines now differ by exactly the intended two casks:

| | MacBook | Studio |
|---|---|---|
| casks | 36 | 38 (+`elgato-camera-hub`, `elgato-wave-link`) |
| formulae | 67 | 71 |
| taps | 0 | 0 |

Four problems surfaced during activation, all now fixed:

1. **`realforce` is a disabled cask** (2026-05-28, vendor download 403s). My
   earlier coverage check read `cask.json` without inspecting the `disabled`
   field, so I wrongly reported it as available. Dropped from the studio
   module; REALFORCE Connect stays a manual install.
2. **`ollama`, `syncthing` and `tailscale` were renamed upstream** to their
   `-app` tokens and were only resolving through deprecation warnings.
   Declarations now use the canonical names. Note the CLI comes with the app:
   `/opt/homebrew/bin/tailscale` is a symlink to
   `Caskroom/tailscale-app/1.86.4/tailscale.wrapper.sh`.
3. **Orphaned tap formulae blocked the whole bundle run.** Removing the taps in
   the previous session left installed formulae whose tap was gone, and
   `brew bundle` aborts on the first unresolvable one:
   `Error: No available formula with the name "slp/krun/gvproxy"`, then
   `takenpilot/cbor/cbor-cli`, then `pulumi/tap` refusing to untap. Cleared with
   `brew uninstall --ignore-dependencies` (cbor-cli needed `--force` because its
   tap was already gone). Lesson: untapping and uninstalling must happen in the
   same pass, or the leftovers wedge every later activation.
4. **The Studio's Homebrew was too old for the `zoom` cask** — 6.0.6 vs the
   MacBook's 6.0.18 — failing with `unknown install step: terminate_process`.
   `brew update` on the Studio fixed it. `onActivation.autoUpdate = false` means
   Homebrew itself never updates during activation, so this will recur.

Cosmetic leftover: `/opt/homebrew/Caskroom/{ollama,syncthing,tailscale}` still
hold stale directories from the pre-rename tokens (0.11.10, 1.30.0-1, 1.86.4),
so `brew list --cask` counts both names. They resolve to the same casks as the
`-app` tokens, so uninstalling by the old name would remove the live app.
Leaving them.


## 2026-08-22 15:50 — Syncthing: current state and whether the star topology is needed

Surveyed before answering.

Both Macs still run Syncthing 2.x (MacBook 2.1.2-1, Studio 2.0.14-1) with two
folders each, **shared only with the dead NAS**, never with each other:

| Folder ID | Label | Path | MacBook | Studio |
|---|---|---|---|---|
| `p6f3q-wfq4t` | Work | `~/work` | 137 GB | 123 GB |
| `uqmgt-4j7hk` | Code | `~/code` | 63 GB | 46 GB |

Devices: MacBook `SPFY23F`, Studio `U3DCZMT`, NAS `T4UIVBG`. The old NAS
(`192.168.2.30`) is **down** — no ICMP, no SSH — so nothing has synced for some
time and the two Macs cannot reach each other at all: they have never been
introduced.

Content profile, which is the decisive fact:

- `~/code`: 76 git repos, **61 Worktrunk `.wt` worktrees**.
- `~/work`: 77 git repos, 71 GB in `catalyst-world` alone, plus 60
  `node_modules`, 49 `build`, 45 `dist`, 19 `.venv`, 16 `.terraform`, 10
  `target` directories.

So ~200 GB across ~153 git repositories and their build output — almost
entirely reproducible or already replicated by git remotes.

Conclusions given to Josh: the star was never required (Syncthing is
peer-to-peer; the hub existed only because the Macs were never peered), the
always-on role the NAS played is now filled by the never-sleeping Studio, and
Syncthing is the wrong mechanism for git trees — `.git` has no transactional
guarantee under file-level sync, and Worktrunk worktrees embed absolute paths
into `.git` files that are machine-specific. Also flagged that simply peering
the two Macs now would union-merge two divergent 130 GB trees, resurrecting
deletions and producing `.sync-conflict` files across 153 repos.

Re-establishing a NAS peer is blocked anyway: nas01's `hdd` pool is OS-level
only and Incus wiring waits on the object-storage design (T16).


## 2026-08-22 16:30 — Conversation continuity: correcting the SQLite claim

Josh's real requirement is conversation continuity between the two Macs. I
previously said "don't sync `~/.omp`" because of SQLite. That was too broad —
checked the actual layout and the docs
(`omp://session-switching-and-recent-listing.md`, `omp://session-operations-*`).

**omp sessions are plain files, not a database.**

- Layout: `~/.omp/agent/sessions/<encoded-cwd>/<timestamp>_<uuid>.jsonl`, with a
  sibling `<timestamp>_<uuid>/` directory holding that session's artifacts.
- `<encoded-cwd>` is the path-encoded canonical cwd — `-code-lab2`,
  `-code-ovh`, and so on. **Both machines are `/Users/josh`, so bucket names
  match exactly.**
- Listing and resume scan the filesystem: `getRecentSessions` reads a 4 KiB
  prefix per file, `SessionManager.list/listAll` read a 4 KiB prefix plus a
  32 KiB tail, sorted by mtime. `--resume <id>` matches on filename/id prefix.
  **No database is consulted to find or open a session.**
- `history.db` only augments the picker's *search* with prompt history. Losing
  it degrades search, not resume.

Composition of the 4.1 GB: 1,248 `.jsonl` transcripts (1.9 GB) and 4,342
`.log` artifacts (2.2 GB), plus md/txt/go/py artifacts. The SQLite files
(`agent.db`, `history.db`, `models.db` and their `-wal`/`-shm`) all sit at the
top of `~/.omp/agent/`, **outside** `sessions/`.

So a Syncthing folder scoped to `~/.omp/agent/sessions/` is viable and is the
one place in this whole session where Syncthing is the right tool: append-heavy
plain files, written on one machine at a time.

Must stay machine-local: `agent.db`, `history.db`, `models.db`,
`terminal-sessions/` (breadcrumbs keyed by TTY/`TMUX_PANE`/`TERM_SESSION_ID`),
`run/`, `cache/`, `ssh-control/`, `install-id`, `puppeteer/`.

Known write hazard: sessions are not purely append-only. The title slot is
fixed-width and rewritten in place, compaction rewrites entries, and the docs
mention an EPERM atomic-rewrite fallback that leaves `.bak` files which
directory scans repair. Sequential use is fine; simultaneous use of the same
session on both machines would produce `.sync-conflict` files.

Paseo, for comparison: `~/.paseo/agents/<encoded-cwd>/<uuid>.json`, 98 files,
392 KB total. Each is workspace metadata only — `id`, `provider` (`omp`),
`cwd`, `workspaceId`, `title`, `lastStatus`, timestamps. **No conversation
content**; Paseo delegates to the provider, so syncing omp sessions covers the
conversations and Paseo's registry is a tiny optional extra.
`daemon-keypair.json` and `cli-client-id` are machine identity and must not
travel.


## 2026-08-22 17:05 — Syncthing rebuilt as a two-Mac mesh

Purged the old star topology and replaced it with direct peering. Driven
through both Syncthing REST APIs (keys read from each machine's `config.xml`).

Removed on both machines: folders `p6f3q-wfq4t` (Work → `~/work`) and
`uqmgt-4j7hk` (Code → `~/code`). Folder definitions only — **no data deleted**.
Josh wants those reconsidered later.

Peered the Macs directly for the first time:

- MacBook `SPFY23F-G6F6HZL-GP7JFYE-A6F6RRX-JZN5ARQ-2UVMEG3-XGPVDSO-K3M5HA3`
- Studio `U3DCZMT-NSJAZ54-ZOCU7VE-5LZDRGN-WDCUL3Q-RA2SVMG-OAQ3Y6R-2OJPEQJ`

Connection is direct LAN, not relayed: `192.168.1.10:22000`, `tcp-client`,
TLS1.3-AES128-GCM.

New folders, `sendreceive` on both sides, fs-watcher on with a 10 s delay,
hourly rescan, no versioning:

| ID | Path | Size |
|---|---|---|
| `omp-sessions` | `~/.omp/agent/sessions` | 4.37 GB / 7,271 files |
| `paseo-agents` | `~/.paseo/agents` | 98 files, 392 KB |

`*.log` files are **included** at Josh's request, so old tool-output artifacts
stay reachable via `artifact://`.

Deliberately excluded (still machine-local): `agent.db`, `history.db`,
`models.db` and their `-wal`/`-shm`, `terminal-sessions/` (breadcrumbs keyed by
TTY / `TMUX_PANE` / `TERM_SESSION_ID`), `run/`, `cache/`, `ssh-control/`,
`install-id`, `puppeteer/`, plus Paseo's `daemon-keypair.json` and
`cli-client-id`.

Verified: `paseo-agents` reached parity at 98/98 files on both machines.
`omp-sessions` is transferring; a session file that landed on the Studio parses
as 473 valid JSONL lines with an intact title record, and the bucket names
(`-code-lab2`, `-code-imgoci-spec`, …) match the MacBook's exactly, which is
what makes cross-machine `--resume` work.

Throughput is ~560 KB/s (11.2 MB per 20 s measured on the wire), so the initial
4.3 GB pass needs roughly two hours. No bandwidth limits are configured on
either side — it is small-file overhead, and the MacBook is on Wi-Fi while the
Studio is wired. Subsequent syncs are incremental and will be trivial.

Note `~/.omp` did not exist on the Studio at all — Syncthing created the tree.
`omp` itself is **not installed** there yet, so the sessions will be waiting for
it rather than immediately usable.

Left in place: the dead `NAS` device (`T4UIVBG`) is still registered on both
machines but now shares no folders, so it is inert.


## 2026-08-22 17:35 — omp and Paseo on the Studio

Josh was half right. The application catalog only walked `/Applications` and
`~/Applications`, so it never covered CLIs.

**Paseo was already fixed.** `Paseo.app` 0.4.0 is on the Studio because the
cask work earlier today declared `paseo`, and the cask ships the CLI too:
`/opt/homebrew/bin/paseo` exists on both machines. What was missing was only
`~/.paseo` state, which Syncthing now carries.

**omp genuinely was missing**, and the catalog could never have caught it: it
is a bun global, not an application and not a Homebrew package —
`~/.bun/install/global/node_modules/@oh-my-pi/pi-coding-agent`, linked as
`~/.bun/bin/omp`. Installed 17.3.4 on the Studio to match the MacBook exactly.
Both machines block the same two postinstalls (`onnxruntime-node`,
`protobufjs`), so that is parity rather than a defect.

Made it declarative in `6f9c828` — new `home/omp.nix`:

- Installs `@oh-my-pi/pi-coding-agent` during home-manager activation **only
  when `~/.bun/bin/omp` is missing**. Presence check rather than a pinned
  version, because omp releases often and Nix should not fight manual upgrades.
- A failed install prints guidance instead of aborting the switch, so a machine
  without network still activates.
- Darwin-only; the Linux home configuration does not run agents.
- `bun` itself already comes from nixpkgs (1.3.14 on both) and `~/.bun/bin` is
  already on `PATH` from `home/shell.nix`, so the only missing piece was the
  package.

Also copied `~/.omp/agent/config.yml` (model roles, theme, task agent
overrides) to the Studio by hand. It sits beside the SQLite files, outside the
synced `sessions/` folder, so it is not covered by Syncthing. It is small and
declarative but omp rewrites it at runtime (`setupVersion`, theme), so a
read-only Nix store symlink would break it — left as a manual copy for now.

Auth stays machine-local by design: omp credentials live in `agent.db`, so the
Studio needs its own sign-in.

Sync progress at this point: 4,107 of 7,287 files, 1.17 of 4.37 GB.


## 2026-08-22 17:55 — Agents and roles: they were not synced; now mostly are

Josh asked whether omp's agents and role configuration travel. They did not —
the first pass only covered `sessions/`.

What each thing actually is, per `omp://task-agent-discovery.md`:

- **User task agents**: `~/.omp/agent/agents/*.md` — 17 definitions
  (`planner`, `programmer`, `reviewer`, `security-reviewer`,
  `complexity-reviewer`, `qa`, …), 72 KB. Discovery order is project
  `.omp/agents` → user `~/.omp/agent/agents` → extension roots → Claude plugin
  roots → bundled, first-wins by exact name. **Absent on the Studio.**
- **Roles**: `modelRoles` and `task.agentModelOverrides` in
  `~/.omp/agent/config.yml`. Agent frontmatter refers to roles as `@review`,
  `@fast_worker`; the concrete selector lives in `modelRoles`, so an agent file
  without its role mapping resolves differently or not at all. Task model
  precedence is `task.agentModelOverrides[name]` → frontmatter `model` list →
  parent's model.
- **Extensions**: `~/.omp/agent/extensions/gitnexus-steering.ts`, 8 KB.
  Extension roots also contribute their own `agents/` directories.

Added two more Syncthing folders — siblings of `sessions/`, so no nesting
conflict:

| ID | Path | Files |
|---|---|---|
| `omp-agents` | `~/.omp/agent/agents` | 17 |
| `omp-extensions` | `~/.omp/agent/extensions` | 1 |

Both reached parity within seconds. Verified the Studio's agent list is
byte-identical to the MacBook's.

**`config.yml` remains the one unsynced piece.** It is a file, not a directory,
so it cannot be a Syncthing folder root, and it sits beside the SQLite files so
its parent cannot be one either. Right now both machines match
(md5 `0de0324f…`) only because I copied it by hand.

Options recorded for later:

1. Move the real file into a synced directory and symlink
   `~/.omp/agent/config.yml` at it. Works only if omp appends/rewrites in place;
   if it writes a temp file and renames over the path, the rename replaces the
   symlink with a regular file and parity silently stops. The presence of
   `config.yml.lock` hints at locked writes but does not settle the question.
2. Re-root the sync at `~/.omp/agent` with an allowlist ignore file
   (`!/agents/**`, `!/extensions/**`, `!/config.yml`, `!/sessions/**`, then
   `*`), replacing the three folders with one. Cleanest long term; costs a
   re-scan of 4.37 GB, though Syncthing would match the existing files by hash
   rather than re-download them.
3. Leave it manual. It changes rarely — model role edits and theme changes.

Not doing anything irreversible while the initial 4.37 GB transfer is still in
flight.

## 2026-08-22 18:05 — Initial sync complete

`omp-sessions` finished: **7,288/7,288 files, 4.37/4.37 GB**. Whole-tree parity
confirmed independently of Syncthing's own accounting — `find | wc -l` returns
7,290 files on both machines, and per-file md5s across all 74 `-code-lab2`
transcripts match exactly.

A first hash-of-hashes comparison disagreed, then matched on retry: the
difference was this very session's transcript being appended to mid-check, not
a sync fault.

Four folders now replicate between the Macs: `omp-sessions`, `paseo-agents`,
`omp-agents`, `omp-extensions`.


## 2026-08-22 18:40 — MCP dependencies made portable; totem moved to the Studio

### 1. Portable commands

`~/.omp/agent/mcp.json` no longer names machine-specific paths:

- `gitnexus`: `/Users/josh/.nodenv/shims/gitnexus` → `gitnexus` (PATH).
- `1password`: added as
  `/Applications/1Password.app/Contents/MacOS/1password-mcp`. Provenance
  resolved — `/usr/local/bin/1password-mcp` was a root-owned symlink into the
  1Password app bundle, and the app is a declared cask, so the in-bundle path
  exists identically on both machines. Verified: same binary, same 4,001,936
  bytes on each.
- `bitwarden`: added as `bw-mcp` (PATH).

### 2. bun globals instead of nodenv globals

`bun add -g gitnexus` on both machines (1.6.9 each). Declared in a new
`home/agents-cli.nix` with the same presence-check activation used for omp.

`bw-mcp` provenance resolved: it was a hand-written `/Users/josh/.local/bin`
shell script that reads a shared session token from
`~/.config/bitwarden-agents/session` and execs `npx -y @bitwarden/mcp-server`.
Now generated by Nix via `pkgs.writeShellScript`, linked to
`~/.local/bin/bw-mcp` (already on PATH from `home/shell.nix`), and switched
from `npx` to `bunx` so it does not depend on a nodenv-managed Node. Smoke
tested: it resolves and launches `@bitwarden/mcp-server`.

### 3. totem relocated to the Studio

The thing needing an always-on host is not the MCP server — it is the
**OpenAI Secure MCP Tunnel bridge**. `compose.yaml` runs
`local/totem-whoop:1.4.4-tunnel-0.0.11` (`restart: unless-stopped`,
`127.0.0.1:65497:8080`) and it had been up **7 days** on the MacBook, which is
exactly the thing that dies when the lid closes.

Moved it:

- Cloned `git@github.com:thebriangao/totem.git` to `~/tools/totem-whoop` on the
  Studio. Note `compose.yaml`, `Dockerfile.tunnel` and `COMPOSE.md` are
  **untracked local files** — not in the repo — so they were copied across
  explicitly, along with `.env`, `tunnel-client.yaml`, and
  `secrets/openai-tunnel-api-key` (chmod 600).
- Stopped the MacBook stack **first** (`docker compose down`) so two tunnel
  clients never hold the same API key simultaneously, then built and started on
  the Studio.
- Verified: container healthy, `/readyz` returns `ready`, logs show
  `tunnel metadata fetched` and `🟢 tunnel-client started`.
- Removed the `[mcp_servers.totem]` block from the MacBook's
  `~/.codex/config.toml`, and added `totem` to the **Studio's**
  `~/.omp/agent/mcp.json` only, as `bunx @thebriangao/totem@1.4.4` — the
  package is published on npm, so the Studio does not need the local checkout
  for the MCP server itself.

This is the first genuinely machine-specific piece of configuration, and it
works because `~/.omp/agent/mcp.json` is deliberately **not** in any Syncthing
folder. If MCP config ever becomes shared, totem needs either a host guard or
promotion to an HTTP endpoint over the tailnet.

## 2026-08-22 18:55 — totem is tunnel-only now

Josh's call: keep the OpenAI tunnel bridge, drop totem as an MCP entirely.

Removed:

- `totem` from the Studio's `~/.omp/agent/mcp.json` (it was only added minutes
  earlier).
- A **malformed remnant** in the MacBook's `~/.codex/config.toml`. My earlier
  regex deletion of `[mcp_servers.totem]` had stripped the header and
  `command`, leaving the `args` value promoted into a bogus table header:
  `["/Users/josh/tools/totem-whoop/dist/server.js"]` with `cwd`,
  `startup_timeout_sec` and `tool_timeout_sec` under it. Cleaned properly and
  verified the file now parses: `tomllib` returns exactly `context7`, `exa`,
  `chrome-devtools`, `node_repl`, `computer-use`, `agentmail`, `bitwarden`,
  `1password`.
- The npm global link `@thebriangao/totem@1.4.4 -> ~/tools/totem-whoop`, which
  existed only to resolve the MCP binary. The checkout itself is untouched.

Audited every agent config on both machines for `totem`: zero matches in
`mcp.json`, `config.toml`, `.claude.json`, `.cursor/mcp.json`, and
`.gemini/settings.json`.

The tunnel keeps running on the Studio: container healthy,
`restart=unless-stopped`, `/readyz` returns `ready`. It is now a plain
background service with no agent-facing surface — which also removes the
machine-specific MCP entry that would have complicated sharing `mcp.json`
later.


## 2026-08-22 19:30 — exa dropped; Phase 4 (skills) complete

`exa` removed from `mcp.json` on both machines — Josh has not seen agents use it
and the account is likely out of credits. Keep-set is now **9 servers**:
browserless, cloudflare-api, context7, agentmail, gitnexus, bitwarden,
1password, adrafinil, chrome-devtools. The exposed `EXA_API_KEY` is therefore
moot, though it still sits in `~/.claude.json` until the purge.

### Skills reconciled

Three-way comparison came out cleaner than expected: `~/code/agent-skills` is
**byte-identical** to `~/.claude/skills` for all 25 shared skills, so the
earlier "`cli/SKILL.md` differs" divergence was the **codex** copy being stale,
not the claude one. Two skills existed only in the materialized copy
(`language-style`, `tmux-interactive`) and two more were untracked working-tree
directories (`cue`, `new-repo-go`).

Promoted all four into the repo (`ccf337b`), so it now holds 27 skills and is
the complete source of truth. The Studio's checkout had the same two untracked
directories with identical hashes; verified, removed, pulled. Both checkouts now
sit at the same commit, and both had **no upstream tracking configured** —
fixed.

Discovered the repo already carried its own materialization mechanism:
`sync.sh <dest>` plus a justfile with `claude` and `codex` targets that rsync
`--delete` into each tool's directory. That is exactly how the copies drifted —
each target was last run at a different time.

### Rendering

New `home/skills.nix` points `~/.agents/skills` at the live checkout using
`config.lib.file.mkOutOfStoreSymlink`, rather than copying into the Nix store:

- omp's `agents` provider treats `~/.agents/skills` as the canonical
  user-level root, with an `enableAgentsUser` toggle independent of the
  claude/codex providers — so it survives Phase 3.
- An out-of-store symlink means editing a skill takes effect immediately: no
  rebuild, no rsync. Verified live — a probe file created in the checkout
  appeared instantly under `~/.agents/skills`.
- omp enumerates one level deep for `<name>/SKILL.md`, so the repo's
  `README.md`, `justfile`, `sync.sh`, `LICENSE-*` and `.git` are ignored rather
  than mistaken for skills.

Applied to both machines: 27 skills each, directory lists identical.

Deleted `~/.codex/skills/.system/` (the 6 vendor skills: `skill-creator`,
`review-agent`, `imagegen`, `openai-docs`, `plugin-creator`,
`skill-installer`) per Josh's decision.

Added a `just omp` target to the skills repo as a fallback for any machine
without the Nix configuration.

### Remaining

- **Phase 3** — set `disabledProviders: [claude, codex, gemini, cursor]`. Now
  unblocked, since `~/.agents/skills` is populated on both machines. Josh should
  run `/mcp list` before and after.
- **Phase 5** — purge `~/.codex ~/.gemini ~/.claude ~/.claude.json` after the
  soak; tarball first.

## 2026-08-22 19:50 — Skills checkout now self-bootstrapping

Josh spotted the fragility: `mkOutOfStoreSymlink` deliberately points outside
the Nix store, so Nix names `~/code/agent-skills` but never creates it. On a
machine without that checkout the symlink dangles.

Closed it in `home/skills.nix` with an `entryBefore ["writeBoundary"]`
activation step that clones the repository when `~/code/agent-skills/.git` is
absent. `meigma/agent-skills` is **public**, so the clone uses HTTPS and needs
no credentials — which matters because the Studio still has no GitHub-authorized
SSH key. Verified by cloning into a throwaway HOME with no auth: 27 skills.

Properties kept deliberately:

- An existing checkout is never touched — no pull, no reset. Local edits are the
  whole point of the out-of-store symlink.
- A failed clone warns instead of breaking activation.
- If the checkout is missing anyway, omp treats an unreadable skills directory
  as empty rather than failing.

The existing checkouts keep their `git@github.com:` SSH remotes; only a fresh
clone uses HTTPS.

Applied to both machines: 27 skills each, activation clean.

## 2026-08-22 20:20 — Phase 3 applied

Josh's call: `agent-skills` stays inside the future `~/code` sync, not excluded.

### The near-miss

Before flipping `disabledProviders` I checked what else the `codex` provider was
supplying, and found `~/.codex/AGENTS.md` — 1,068 bytes of Josh's standing
"prefer agile, avoid waterfall, don't be pedantic" guidance. Per
`omp://context-files.md`, **only one user-scope context file survives across all
providers**, and with no native file present the `codex` one (priority 70) was
it. Disabling `codex` would have silently dropped that guidance from every
session.

Copied it to `~/.omp/agent/AGENTS.md` (native, priority 100 — shadows every
other user-level candidate) on both machines, md5 `10e33f2a` each. Verified
after the change that omp injects it: a headless probe quoted
`/Users/josh/.omp/agent/AGENTS.md` back.

Other user-scope candidates were all absent or empty: `~/.claude/CLAUDE.md`
(absent), `~/.gemini/GEMINI.md` (0 bytes), opencode, `~/.agent{,s}/AGENTS.md`.

### Applied

```yaml
disabledProviders: [claude, codex, gemini, cursor]
```

Both machines. Verified `omp config get disabledProviders` returns the array.

### Verification

Headless probe on the MacBook after the change:

- **8 MCP servers**: adrafinil, bitwarden, browserless, chrome-devtools,
  cloudflare-api, context7, gitnexus, 1password.
- **27 skills** — matching `~/.agents/skills` exactly.
- User context file loading from the native path.

`agentmail` is the ninth declared server and does **not** connect. Probed the
endpoint directly: `POST https://mcp.agentmail.to/mcp` returns
`{"error":"Unauthorized"}`, and a bare GET returns 405. It needs an OAuth
credential that this profile never held — so it was already dead before Phase 3,
not a regression. Either `/mcp reauth agentmail` or drop it.

The Studio's config is identical (same `mcp.json`, same `config.yml`, 27 skills)
but omp cannot run there yet: no provider credentials. That is the expected
machine-local auth boundary — credentials live in `agent.db`, which is
deliberately unsynced. It needs a one-time sign-in before functional parity can
be confirmed.

Remaining: Phase 5 purge (soaking), then the `~/code` / `~/work` sync.

## 2026-08-22 20:30 — agentmail removed; declared set now equals connected set

Dropped `agentmail` from `~/.omp/agent/mcp.json` on both machines. It had no
usable OAuth credential and returned `{"error":"Unauthorized"}`.

Final MCP set — **8 servers, and for the first time the declared count matches
the connected count exactly**:

| Server | Transport | Resolution |
|---|---|---|
| `browserless` | http | `mcp.browserless.io/mcp` |
| `cloudflare-api` | http | `mcp.cloudflare.com/mcp` |
| `context7` | http | `mcp.context7.com/mcp` |
| `gitnexus` | stdio | `gitnexus mcp` (bun global, PATH) |
| `bitwarden` | stdio | `bw-mcp` (nix-generated wrapper, PATH) |
| `1password` | stdio | in-bundle binary from the declared cask |
| `adrafinil` | stdio | in-bundle helper from the declared cask |
| `chrome-devtools` | stdio | `bunx chrome-devtools-mcp@1.7.0` |

Verified live: 8 servers visible, 27 skills, native user context loading. No
absolute machine-specific paths remain, no `npx`, no unpinned `@latest`, and
every stdio binary exists on both machines.

Net effect of the consolidation: from ~20 servers spread across five config
files in four formats — several of them broken or Codex-only — down to 8 working
servers in one file that is identical on both workstations.

## 2026-08-22 20:50 — Phase 5: purged

Backed up first, then deleted `~/.claude`, `~/.codex`, `~/.gemini` and
`~/.claude.json` on both machines.

Backups at `~/backups/agent-configs-2026-08-22/` on each machine, `tar | zstd -3`,
every archive integrity-checked with `zstd -t`:

| Archive | MacBook | Studio |
|---|---|---|
| `.claude.tar.zst` | 145 MB | 5.8 MB |
| `.codex.tar.zst` | 2.0 GB | 340 MB |
| `.gemini.tar.zst` | 2.2 GB | 4.0 MB |
| `claude.json` | 353 KB | — |

Reclaimed **12 GB** on the MacBook and **712 MB** on the Studio.

What the bulk actually was: `.codex` held 4.7 GB of `archived_sessions`, 2.2 GB
of `sessions` and a 1.2 GB `logs_2.sqlite`; `.gemini` was 2.9 GB of
`antigravity` plus a 237 MB browser profile; `.claude` was 618 MB of `projects`.
Almost none of it was configuration — it was conversation history for CLIs Josh
no longer uses. Full-fidelity archives were taken anyway rather than
cherry-picking, so nothing needed a judgment call.

Deliberately kept: `~/.cursor` (Paseo launches `cursor-agent`),
`~/.config/bitwarden-agents/session` (`bw-mcp` reads it), `~/.agents/skills`,
`~/.omp/agent/{AGENTS.md,mcp.json,config.yml}`.

Verified after the purge on the MacBook: **8 MCP servers, 27 skills, user
context still resolving to `/Users/josh/.omp/agent/AGENTS.md`.** Nothing
regressed.

Note the `claude` and `codex` CLIs are still installed (`~/.local/bin/claude`,
`~/.nodenv/shims/codex`). Their configuration is gone, so a future invocation
would start from a clean slate. Removing the binaries was out of scope.

The `EXA_API_KEY` literal disappeared with `~/.claude.json`, but it was already
exposed in a terminal today — still worth rotating at the Exa account.

Consolidation complete: 5 config files in 4 formats with ~20 servers, several
broken, reduced to one 8-server file identical on both machines, plus a single
skills root rendered from one git repo.

## 2026-08-22 21:20 — ~/code and ~/work sync configured

Josh removed `catalyst-world` (70+ GB), so `~/work` on the MacBook is now 26 GB.
Current disk state:

| | MacBook (authoritative) | Studio |
|---|---|---|
| `~/code` | 60 GB | 46 GB |
| `~/work` | 26 GB | 123 GB |

### Authority via folder type, not trust

MacBook folders are **`sendonly`**, Studio folders **`receiveonly`**. That makes
"MacBook is authoritative" a structural property rather than a discipline: the
Studio cannot propagate anything upstream, and its extra content is recorded as
locally-changed rather than pushed. Nothing on the Studio is deleted until an
explicit *Revert local changes*, which is the deliberate gate — `~/work` there
holds ~97 GB the MacBook does not, most of it the deleted `catalyst-world`.

Staggered versioning (30 days) on both sides, so a revert archives into
`.stversions` instead of destroying.

### Ignore list

Identical `.stignore` in all four folder roots (md5 `32e72022`), using `**/name`
form with the `(?d)` deletable prefix. Excludes `.wt` worktrees first and
foremost — 59 of them in `~/code`, each carrying absolute `gitdir` paths that
would make the two machines disagree about which worktrees exist — then
`node_modules`, `target`, `dist`, `build`, `.venv`, `__pycache__`,
`.terraform`, `.direnv`, `result`, plus disk images and editor noise.

**It works:** the MacBook's `~/code` indexed 4.5 GB against 60 GB on disk, and
39,133 files against a tree that holds far more. `ignorePatterns: true` is
reported on the folder, confirming Syncthing loaded the file.

### First observation of the reconcile problem, quantified

The Studio's `code` folder immediately reported **92,872 locally-changed files
totalling 12.9 GB** — content it has that the MacBook does not. That is exactly
the union-merge hazard the design flagged, and it is now parked behind the
receive-only gate instead of silently resurrecting on the MacBook.

Scans are still running (both `work` folders had not started indexing yet). The
initial pass is expected to take hours; `~/code` alone is ~24,000 directories.

Next: let the scans finish, then decide per folder whether to revert the
Studio's local changes (making it a true mirror) before flipping both sides to
`sendreceive` for two-way operation.
