# Homebrew cleanup dry run — 2026-08-22

Pending change to `configuration.nix`: drop `claude`, `logseq`, `readdle-spark`,
`visual-studio-code` from `casks`, and set `homebrew.onActivation.cleanup = "uninstall"`.
**Not applied.** Output of `brew bundle cleanup` against the rendered Brewfile on each machine.

## Casks

| Cask | MacBook | Studio |
|---|---|---|
| claude | uninstall | uninstall |
| goreleaser-pro | uninstall | — |
| logseq | uninstall | uninstall |
| multipass | uninstall | uninstall |
| readdle-spark | uninstall | uninstall |
| visual-studio-code | uninstall | uninstall |

## Formulae

MacBook 114, Studio 38. Homebrew keeps dependencies of declared packages, so this is
genuinely unreferenced software, not transitive deps.

### Tools in active use that would disappear

   `age`, `ansible`, `bazelisk`, `bitwarden-cli`, `cilium-cli`, `codex`, `container`, `d2`, `direnv`, `ffmpeg`, `flyctl`, `gemini-cli`, `gnupg`, `go`, `golangci-lint`, `helm`, `helmfile`, `hubble`, `incus`, `iperf3`, `k3d`, `libvirt`, `lima`, `mise`, `pandoc`, `pinentry-mac`, `qemu`, `railway`, `ripgrep`, `shellcheck`, `skopeo`, `socat`, `sops`, `talhelper`, `tree`, `worktrunk`

### Removed on both machines

   `ansible`, `bazelisk`, `capstone`, `container`, `cryptography`, `dtc`, `gettext`, `glib`, `gmp`, `gnutls`, `jpeg-turbo`, `libevent`, `libidn2`, `libpng`, `libslirp`, `libsodium`, `libssh`, `libtasn1`, `libunistring`, `libusb`, `libyaml`, `lzo`, `mise`, `ncurses`, `nettle`, `p11-kit`, `pcre2`, `pixman`, `qemu`, `snappy`, `tree`, `unbound`, `usage`, `vde`, `worktrunk`

### MacBook only

   `abseil`, `age`, `aom`, `bash`, `bitwarden-cli`, `cairo`, `cilium-cli`, `codex`, `cunit`, `d2`, `dav1d`, `direnv`, `ffmpeg`, `flyctl`, `fontconfig`, `freetype`, `gemini-cli`, `giflib`, `gnupg`, `gpgme`, `gpgmepp`, `helm`, `helmfile`, `hubble`, `incus`, `iperf3`, `iproute2mac`, `json-c`, `json-glib`, `k3d`, `lame`, `libassuan`, `libde265`, `libgcrypt`, `libgpg-error`, `libheif`, `libiscsi`, `libksba`, `libssh2`, `libtiff`, `libtpms`, `libvirt`, `libvmaf`, `libvpx`, `libx11`, `libxau`, `libxcb`, `libxdmcp`, `libxext`, `libxrender`, `lima`, `little-cms2`, `mtools`, `npth`, `nspr`, `nss`, `openjpeg`, `opus`, `pandoc`, `pinentry`, `pinentry-mac`, `plaid/plaid-cli/plaid`, `poppler`, `protobuf`, `railway`, `ripgrep`, `sdl2-compat`, `semaphoreci/tap/sem`, `shellcheck`, `skopeo`, `socat`, `sops`, `svt-av1`, `swtpm`, `talhelper`, `webp`, `x264`, `x265`, `xorgproto`

### Studio only

   `go`, `golangci-lint`, `python@3.14`

## Taps

- MacBook (11): `goreleaser/tap`, `ironspecs/tap`, `libkrun/krun`, `meigma/tap`, `multica-ai/tap`, `peonping/tap`, `plaid/plaid-cli`, `pulumi/tap`, `semaphoreci/tap`, `tailwarden/komiser`, `withered-magic/brew`
- Studio (3): `homebrew/bundle`, `jmgilman/apps`, `pulumi/tap`

Every tool named above comes from `homebrew/core`, so untapping does not affect them.

