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