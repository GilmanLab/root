---
id: 014
title: Session opened, goal pending
started: 2026-08-24
---

## 2026-08-24 16:35 — Kickoff
Goal for the session: Start a new journal session; the substantive goal has not yet been provided.
Current state of the world: Journal setup is healthy, required context is loaded, and session 013 is the latest completed session.
Plan: Await the user's actual request, then record meaningful checkpoints here.

## 2026-08-24 16:41 — Development VM goal
The substantive goal is to establish a development VM in the Incus lab as the always-on home base for agent work. The VM will run the oh-my-pi CLI harness and Paseo in server mode, replacing the Mac Studio as the primary Paseo server; both the Mac Studio and MacBook will become clients of the lab VM. The immediate next step is to define the VM's access, persistence, placement, resource, and reproducibility requirements before provisioning it.

## 2026-08-24 17:02 — Initial requirements and research
The VM will be pinned to a deliberately lightly loaded Incus node and sized generously: at least 32–48 GiB RAM, 12–16 vCPUs, and several hundred GiB of storage. Josh favors a custom bootc image with Nix for mutable developer tooling, direct tailnet membership with Tailscale SSH, manual `gh` and AWS SSO login, a dedicated agent commit-signing key, and a narrowly scoped 1Password service account. Paseo/OMP already preserve agents across client disconnects and VM restarts.

Graphical computer use is viable on Linux, but OMP's current platform support materially affects the image choice: Linux X11 supports capture, input, and AT-SPI; released Linux Wayland builds omit PipeWire capture and portal input authorization does not persist. Headless OMP browser automation does not need a desktop. Bluefin's default GNOME/Wayland desktop is therefore a poor default if native OMP computer use is required; an X11 desktop in a custom bootc image is the safer prototype.

Official bootc guidance makes the composefs deployment root read-only while `/var` persists. A normal `/nix` store is not turnkey: Fedora's accepted Nix package documentation says `/nix` is incompatible with rpm-ostree and bootc bind-mount integration remains in progress. A custom image can deliberately provide persistent `/nix` storage, but that must be prototyped rather than assumed.

Incus supports scheduled/expiring snapshots, export/import backup files, and copies to another Incus server. Snapshots remain on the source pool and are not sufficient backups. The existing 17.4 TiB `hdd` ZFS pool on nas01 is still OS-level only, so using it requires a separate backup destination/exposure design. Likely policy: local Incus snapshots for fast rollback plus encrypted, deduplicated backup of persistent development state to a service backed by `hdd`; the immutable OS and reproducible Nix store should be rebuilt rather than backed up.
