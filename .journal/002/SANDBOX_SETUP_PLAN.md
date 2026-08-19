# Sandbox Setup Plan — `GilmanLab/sandbox` + `sandbox01` base config (T41)

Status: ready for implementation. Drafted 2026-08-19 in session 002. The
implementing session reports back so session 002 closes T41 on its report.

Self-contained. Context pointers: `.journal/002/VISION.md` (device naming,
Secrets section, session 006 network facts), meta docs
`reference/networking/address-plan.md` and ADR-0002/ADR-0003.

## Goal

Create `GilmanLab/sandbox`: a pyinfra project that is `sandbox01`'s **reset
button** — from fresh Ubuntu 26.04 to fully configured base in one run, then
idempotent thereafter. Then run it against the live box.

## The machine

| Fact | Value |
| --- | --- |
| Host | `sandbox01` (Minisforum UM760, Ryzen 7, 32GB, 1x 2.5GbE `enp2s0`) |
| OS | Ubuntu 26.04 |
| Address | `10.10.40.10/24` (DHCP reservation, VLAN 40 sandbox/workload, gw `10.10.40.1`) |
| Network posture | VLAN 40 cannot initiate to management/OOB (gw01 policy, session 006) |
| Access today | `ssh josh@10.10.40.10` (key auth); passwordless sudo via ad-hoc `/etc/sudoers.d/90-josh-nopasswd` |
| Charter | General-purpose test/spike host. Mutable, expendable, outside the IncusOS cluster. **The deliberate exception to the immutability principle** — say this in the README so nobody "fixes" it. |

## Repo conventions

Mirror `GilmanLab/networking` (the other pyinfra repo — pyinfra is the house
tool for this space, it also drives VyOS there):

- uv project, `requires-python >=3.14`, hatchling, ruff/mypy/pytest dev group,
  mise + moon tasks (`check` = format/lint/type/test).
- Dependencies: `pyinfra`, `pyinfra-incus` (meigma product — pin the released
  version; if unreleased, pin a git ref and note it for re-pin).
- Layout suggestion: `inventory.py` (sandbox01 + `@local` optional), `deploys/`
  (base.py orchestrating focused modules: users, docker, podman, incus,
  tailscale, ssh), `tests/` for whatever pure logic exists (keep ceremony low —
  this is the sandbox's repo, conventions yes, bureaucracy no).
- Repo settings: private, squash-only, auto-delete branches (org norm).
- Wire into lab2 meta `init.sh` beside `networking`/`aws` (meta-repo PR).
- README: charter, immutability-exception note, reset procedure ("reinstall
  Ubuntu 26.04, create josh + key, run pyinfra"), break-glass access.

## Configuration requirements (Josh's list + gaps filled)

### 1. Admin group + users

- Group `admin` with passwordless sudo via managed drop-in
  `/etc/sudoers.d/50-admin` (`%admin ALL=(ALL:ALL) NOPASSWD:ALL`, mode 0440,
  visudo-validated).
- User `sandbox`: home, bash, member of `admin`.
- User `josh`: member of `admin`; authorized_keys pinned to the macOS key
  (breaking-glass identity — fetch the pubkey from the current
  `~/.ssh/authorized_keys` on the box during implementation and pin it in the
  repo; it is public material, safe in git).
- **Retire the ad-hoc `/etc/sudoers.d/90-josh-nopasswd`** once the managed
  drop-in is in place (the reset button must own sudo policy).

### 2. Container runtimes

- Docker (upstream docker.io or Docker CE — implementer's call, pin the
  choice in README) with `josh` and `sandbox` in the `docker` group.
- Podman alongside (Ubuntu archive version fine). Rootless for both users is
  the default posture; note the docker-group = root-equivalent caveat in
  README (moot given NOPASSWD, but say it).
- Coexistence note: both installed is fine; do NOT install
  `podman-docker` (its `docker` shim conflicts with real Docker).

### 3. Incus

- Install Incus (zabbly stable repo for current series, or Ubuntu archive
  LTS — pick and pin; the T32 spike wants a current Incus, lean zabbly).
- Initial setup **via `pyinfra-incus`** (`~/code/meigma/pyinfra-incus`;
  controller-side library, runs `incus` CLI over SSH with `_sudo=True` — no
  agent, no HTTPS listener, keep the Unix socket root-only):
  - storage pool: single NVMe box — `zfs` driver on a loop/dataset if
    zfsutils present, else `dir`; size modest (spikes are throwaway).
  - default bridge network (`incusbr0`) + default profile wiring.
- Convenience vs. purity: add `josh` to `incus-admin` for interactive spike
  work (sandbox charter tolerates it; pyinfra deploys still use sudo per the
  library's guidance).
- This Incus daemon is the T32 spike target (kind + CAPN pivot) — leave it
  vanilla, no cluster, no preseeded projects beyond default.

### 4. Tailscale

- Install tailscaled (official apt repo, pinned).
- **Enrollment is a cross-repo change** — the tailnet policy is GitOps in
  `GilmanLab/networking` (ADR-0002). Companion PR there:
  - add `tag:sandbox` with `autogroup:admin` owner;
  - Tailscale **SSH rules**: allow `josh` (your login) → `tag:sandbox` as
    users `josh`, `sandbox`, and `root` (action `check` for root if you want
    the re-auth prompt; `accept` for the others);
  - any ACL needed for you to reach the box over the tailnet.
- Auth key: generate a tagged, reusable-or-single-use key (or use the
  existing node-registration trust credential if it fits) and store it as the
  **first `sandbox`-scope secret** in `GilmanLab/secrets`:
  - add creation rule `^sandbox/.*\.sops\.ya?ml$` with context
    `Repo: GilmanLab/secrets` / `Scope: sandbox` **plus the PGP encryption
    subkey `51098F038D5D9F84FE342036858A466C85A0979C!`** (NOT the primary
    fingerprint — see ADR-0003 / session 005 lesson);
  - pyinfra decrypts at deploy time on the operator laptop (`lab-admin` SSO);
    no CI IAM role — no CI consumer exists.
- `tailscale up --ssh --auth-key=<from sops>` with tag `tag:sandbox`;
  MagicDNS gives `sandbox01.<tailnet>` for free.

### 5. SSH hardening (ORDER MATTERS — do this LAST)

Only after Tailscale SSH is verified working (`ssh sandbox01` over the
tailnet from the mac, as both `josh` and `sandbox`):

- sshd drop-in `/etc/ssh/sshd_config.d/50-hardening.conf`:
  `PasswordAuthentication no`, `KbdInteractiveAuthentication no`,
  `PermitRootLogin no`, `PubkeyAuthentication yes`, `AllowUsers josh`,
  `X11Forwarding no`, `MaxAuthTries 3`.
- Keep sshd listening on the LAN address — `josh@10.10.40.10` + macOS key is
  the break-glass path when the tailnet is down (VLAN 40 is already
  firewall-isolated; no need to bind-restrict further).
- Validate with `sshd -t` before reload; keep the current session open while
  verifying a fresh connection (standard don't-lock-yourself-out drill).

### 6. Baseline (the "anything else")

- `unattended-upgrades` enabled (security pocket only) — a pet on a lab
  network should patch itself.
- Hostname assertion: deploy asserts `sandbox01` (guards against reimage
  drift; the name is canonical per `reference/naming.md`).
- Minimal tool baseline: git, curl, htop, tmux, build-essential — keep small;
  spikes install their own stacks.
- Timezone/NTP: systemd defaults are fine; set timezone explicitly if desired.
- Do NOT add monitoring/backup agents — expendable by charter.

## Acceptance

1. **Reset-button proof**: documented procedure from fresh-Ubuntu assumptions;
   the deploy runs green end-to-end against the live box.
2. **Idempotence**: immediate second run reports zero changes.
3. Functional smoke, each verified on the box:
   - `sudo -n true` as josh and sandbox (via admin group; ad-hoc drop-in gone);
   - `docker run --rm hello-world` as josh (group membership live);
   - `podman run --rm quay.io/podman/hello` as josh;
   - `incus launch images:alpine/3.22 t1 && incus exec t1 -- true && incus delete -f t1`;
   - `tailscale status` shows the node tagged `tag:sandbox`; `ssh sandbox01`
     over the tailnet works as josh and sandbox (Tailscale SSH, no key);
   - LAN break-glass: `ssh josh@10.10.40.10` with the macOS key still works;
     password auth refused; `ssh sandbox@10.10.40.10` refused (AllowUsers).
4. Cross-repo artifacts merged: networking policy PR (tag + SSH rules),
   secrets PR (`sandbox` scope + auth-key secret), meta `init.sh` PR.
5. Report back to session 002: deviations, pinned versions (Incus channel,
   Docker source, pyinfra-incus version), and confirmation the T32 spike
   host is ready (Incus reachable, vanilla).

## Risks

- **Lockout**: hardening before Tailscale SSH verification, or a bad
  `AllowUsers` line. Mitigation: ordering above + `sshd -t` + keep-session-open
  drill. Worst case: pikvm01/kvm01 console (untested — don't rely on it) or
  physical access.
- **Tailscale SSH vs. sshd hardening interplay**: Tailscale SSH intercepts
  port 22 traffic arriving over the tailnet *before* sshd — sshd hardening
  does not affect tailnet logins. That's the design (primary vs. break-glass),
  but verify both paths independently.
- **Wrong PGP recipient in the new secrets rule** — must be the encryption
  subkey with `!`; the metadata CI guard in `GilmanLab/secrets` should catch a
  bare-fingerprint mistake, but don't rely on it (it checks presence, verify
  it checks exactness).
- **`podman-docker` shim** silently shadowing Docker — exclude it.
- **Zabbly vs. archive Incus drift** — whichever is chosen, pin it and note
  the upgrade posture in README (sandbox may track current deliberately).

## Non-goals

- The T32 spike itself (this plan produces its ready host).
- Joining sandbox01 to anything (no IncusOS, no Incus cluster, no fleet).
- Monitoring, backups, or any durability story — expendable by charter.
- VyOS/gw01 changes beyond the tailnet policy file.
