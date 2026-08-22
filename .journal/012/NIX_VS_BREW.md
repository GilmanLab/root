# Keep list: Nix vs Homebrew — 2026-08-22

Josh's policy: prefer Nix, fall back to Homebrew when the package is missing,
massively outdated, or broken. Nix versions are from the flake's pinned
`nixpkgs` (nixos-unstable) for `aarch64-darwin`.

| Tool | Nix attr | Nix | Brew stable | Installed now | Verdict |
|---|---|---|---|---|---|
| age | `age` | 1.3.1 | 1.3.1 | 1.2.1 | nix |
| ansible | `ansible (=ansible-core)` | 2.21.2 | 14.3.1 | 13.1.0 | nix, with caveat |
| bitwarden-cli | `bitwarden-cli` | 2026.7.0 | 2026.8.0 | 2026.7.0 | nix |
| cilium-cli | `cilium-cli` | 0.19.7 | 0.19.7 | 0.19.1 | nix |
| container | `container` | 1.1.0 | 1.2.2 | 0.7.1 | nix |
| direnv | `direnv` | 2.37.1 | 2.37.1 | 2.37.1 | already nix (programs.direnv) |
| ffmpeg | `ffmpeg` | 8.1.2 | 9.0.1 | 8.0.1_1 | keep brew (major behind) |
| flyctl | `flyctl` | 0.4.79 | 0.4.87 | 0.4.82 | nix |
| gnupg | `gnupg` | 2.4.9 | 2.5.21 | 2.4.9 | already nix (systemPackages) |
| helm | `kubernetes-helm` | 4.2.3 | 4.2.4 | 4.0.4 | already nix |
| helmfile | `helmfile` | 1.7.2 | 1.7.4 | 1.2.2 | nix |
| hubble | `hubble` | 1.19.4 | 1.19.4 | 1.18.6 | nix |
| iperf3 | `iperf3` | 3.21 | 3.21 | 3.20 | nix |
| k3d | `k3d` | 5.9.0 | 5.9.0 | 5.8.3 | nix |
| lima | `lima` | 2.2.0 | 2.2.0 | 2.0.3 | nix |
| mise | `mise` | 2026.7.17 | 2026.8.10 | 2026.6.14 | nix |
| pandoc | `pandoc` | 3.7.0.2 | 3.10.2 | 3.10.1 | keep brew (3 minors behind) |
| pinentry-mac | `pinentry_mac` | 1.1.1.1 | 1.3.1.1 | 1.3.1.1 | keep brew (2 minors behind) |
| qemu | `qemu` | 11.0.3 | 11.1.0 | 10.2.0 | nix |
| ripgrep | `ripgrep` | 15.2.0 | 15.2.0 | 15.1.0 | already nix |
| shellcheck | `shellcheck` | 0.11.0 | 0.11.0 | 0.11.0 | nix |
| skopeo | `skopeo` | 1.24.0 | 1.24.0 | 1.24.0 | nix |
| sops | `sops` | 3.13.3 | 3.13.3 | 3.13.1 | already nix |
| tree | `tree` | 2.3.2 | 2.3.2 | 2.2.1 | nix |
| worktrunk | `worktrunk` | 0.71.0 | 0.74.0 | 0.37.1 | nix, with caveat |

## Caveats

- **ansible**: nixpkgs `ansible` is `ansible-core` 2.21.2. Homebrew's `ansible` 14.3.1 is the
  community bundle (core + collections). Equivalent core, but collections must then come from
  a pinned `requirements.yml`, which the ansible-automation skill prefers anyway.
- **container**: nixpkgs 1.1.0 vs Homebrew 1.2.2 — one minor behind, but far ahead of the
  0.7.1 currently installed.
- **worktrunk**: nixpkgs 0.71.0 vs Homebrew 0.74.0. The installed copy is 0.37.1, so either
  source is a large jump; the `worktrunk` skill is grounded against 0.37.1 and will need
  re-verification.

## Not in the keep list, but flagged

- **`incus` is Linux-only in nixpkgs** (`incus`, `incus-lts`), and there is no `incus-client`.
  Homebrew is the only source on macOS, and this is the CLI used to reach the lab cluster.
  Dropping it removes lab access from both machines.
- Available in nixpkgs if wanted: `codex` 0.147.0, `gemini-cli` 0.47.0, `d2` 0.7.1,
  `talhelper` 3.1.16, `bazelisk` 1.29.0, `socat` 1.8.1.3, `railway` 5.30.4,
  `golangci-lint` 2.12.2, `pulumi` 3.255.0, `nodejs` 24.18.1.

## `go`

`brew uses --installed go` on the Studio returns exactly `golangci-lint`, and
`brew deps golangci-lint` is `go`. So `go` is a Homebrew dependency, not a manual install.
Homebrew's cleanup keeps dependencies of *declared* packages: declare `golangci-lint` and `go`
is retained automatically; declare neither and both go. `goenv` is unaffected either way —
it downloads and builds its own toolchains under `~/.goenv`.

