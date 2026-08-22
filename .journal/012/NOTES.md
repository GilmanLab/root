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