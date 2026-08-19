---
id: 007
title: Review sandbox setup plan
started: 2026-08-19
---

## 2026-08-19 11:35 — Kickoff
Goal for the session: Start a fresh session and read session 002's `SANDBOX_SETUP_PLAN.md` in preparation for the user's next request.
Current state of the world: Session 002 contains a ready-for-implementation plan for creating `GilmanLab/sandbox` and configuring the live `sandbox01` host; sessions 004–006 completed related AWS, secrets, and gateway work.
Plan: Load the sandbox setup plan in full, summarize readiness and constraints, then await the user's implementation direction.

## 2026-08-19 11:36 — Sandbox plan loaded
Read session 002's `SANDBOX_SETUP_PLAN.md` in full. It is ready for implementation and covers the private `GilmanLab/sandbox` pyinfra repository, live `sandbox01` convergence, companion networking/secrets/meta changes, lockout-safe SSH hardening, idempotence, functional smoke tests, and reporting pinned implementation choices back to session 002. No implementation has started.


## 2026-08-19 15:45 — T41 implemented; report for session 002

T41 is complete. The implementation was merged through four squash PRs:

- `GilmanLab/root` PR #16 (`feat: bootstrap sandbox repository`) adds the private sandbox repository to `init.sh`.
- `GilmanLab/networking` PR #9 (`feat(tailscale): authorize sandbox hosts`) adds `tag:sandbox`, tag ownership by `autogroup:admin`, and Tailscale SSH rules for josh, sandbox, and root.
- `GilmanLab/secrets` PR #23 (`feat(sops): add sandbox enrollment client`) adds `sandbox/tailscale.sops.yaml` under the scoped KMS + exact Curve25519 encryption-subkey recipient rule.
- `GilmanLab/sandbox` PR #1 (`feat: add sandbox01 reset automation`) adds the reset-button pyinfra project, CI, operator README, deploy/harden split, and live-tested host configuration.

Implementation choices and deviations from the handoff plan:

- Replaced a stored reusable Tailscale auth key with a non-expiring OAuth client constrained to `auth_keys` scope and `tag:sandbox`. The controller decrypts the OAuth credentials only when an unenrolled host is detected, mints a single-use, preauthorized, non-ephemeral key with a 10-minute TTL, writes it to root-only `/run`, runs `tailscale up`, and shreds the file on success or failure. Idempotent runs make no Tailscale API request.
- Incus tracks Zabbly `stable` for Ubuntu `resolute`; live version was `1:7.3-ubuntu26.04-202608160201`. `pyinfra-incus` is pinned exactly at `0.2.0`. The daemon remains vanilla: one 50 GiB loop-backed ZFS `default` pool, `incusbr0`, no cluster, no IncusOS, no projects, no monitoring, and no backup policy.
- Docker comes from the Ubuntu 26.04 archive (`docker.io`, `docker-buildx`, `docker-compose-v2`, `containerd.io`) because Docker CE did not publish a `resolute` suite. The deploy removes any stale Docker CE source/key. Podman also comes from the Ubuntu archive and `podman-docker` is kept absent.
- Tailscale uses the official stable repository pinned to its supported `noble` suite because no `resolute` suite exists. Repository refreshes use content-derived remote markers so immediate reruns report no changes; packages are not force-upgraded on every deploy. Ubuntu unattended upgrades are limited to the security pocket with no automatic reboot.
- The Mac's accepted tailnet subnet route for VLAN 40 superseded its physical route and made direct LAN SSH to `10.10.40.10` fail after enrollment. The repository therefore tracks `ssh_config` with a physical `ProxyJump` through `gw01` at `10.0.0.2`; pyinfra and the documented break-glass command use that path. This preserves access independently of Tailscale while keeping strict host-key checking.
- sshd hardening remains a separate final command. It atomically stages `50-hardening.conf`, validates with `sshd -t`, removes cloud-init's earlier `50-cloud-init.conf` password override in the same operation, installs, and reloads. Effective state is `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin no`, `PubkeyAuthentication yes`, `AllowUsers josh`, `X11Forwarding no`, and `MaxAuthTries 3`.

Verification against live `sandbox01`:

- Repository check passed: lock validation, Ruff format/lint, mypy, and 23 pytest tests. Both final GitHub Actions workflows passed.
- Full deploy converged successfully, then an immediate rerun reported zero changes for all 37 base operations. A second hardening run also reported zero changes.
- Functional smoke passed: passwordless sudo for josh and sandbox with the ad-hoc sudoers file absent and managed mode `0440`; Docker hello-world; rootless Podman hello; Incus Alpine 3.22 launch/exec/delete; running `tag:sandbox` Tailscale identity; josh and sandbox Tailscale SSH.
- Post-hardening access passed independently: josh LAN key login through the physical gateway plus passwordless sudo; josh and sandbox Tailscale SSH plus passwordless sudo. Effective sshd state disables password authentication and restricts direct sshd logins to josh.
- T32 is ready: Incus is reachable, the Alpine container smoke passed, and no opinionated Incus configuration was added.

The live host was not destructively reset, per Josh's instruction. The README documents the fresh-Ubuntu reset procedure; the deploy was exercised end-to-end against the existing Ubuntu 26.04 host and proved convergent and idempotent.


## 2026-08-19 16:06 — Correction: physical lab route is inactive on rtr01

Follow-up routing diagnosis corrected the earlier ProxyJump explanation. The Mac does not need a host route; without accepted Tailscale routes it sends `10.10.40.10` to its default gateway `rtr01` at `192.168.1.1`. The intended `rtr01` static route `10.10.0.0/16 via 10.0.0.2` exists but is inactive (`I s`, empty `immediate-gw`) because it uses `check-gateway=ping` and `rtr01` cannot ping `gw01` from transit source `10.0.0.1`. The deployed `gw01` `WAN_LOCAL` chain allows ICMP only from `HOME_NETWORKS`, so it drops that health probe. RouterOS consequently resolves lab traffic through its internet default route instead. A Mac-sourced ping to `10.0.0.2` succeeds because `192.168.1.20` matches `HOME_NETWORKS`; `10.10.40.1` and physical direct SSH time out. The source fix belongs in the tracked gateway firewall: permit ICMP from the transit router (narrowly `10.0.0.1`) so the static route becomes active. Tailscale subnet routing masked this defect before `sandbox01` enabled Tailscale SSH.


## 2026-08-19 16:15 — Physical home-to-lab routing repaired

Networking PR #10 (`fix(vyos): restore physical lab routing`) merged as `3fdf1a3`. The tracked `gw01` `WAN_LOCAL` policy now permits ICMP from the single transit-router address `10.0.0.1`, with a regression assertion in `tests/test_policy.py`. The corrected full gateway configuration synchronized, verified, saved, and finished with accepted state. `rtr01` immediately changed `10.10.0.0/16 via 10.0.0.2` from inactive to active (`immediate-gw=10.0.0.2%DOWNLINK`); three gateway probes returned with 0% loss. With Mac Tailscale subnet-route acceptance temporarily disabled, the physical route used `en0` through `192.168.1.1`, `10.10.40.1` answered ICMP, and direct key SSH plus passwordless sudo on `sandbox01` succeeded. Tailscale route acceptance was restored and Tailscale SSH still succeeded. Repository validation passed all 41 tests, formatting, linting, typing, lock, and VyOS template checks; PR CI passed. The implementation worktree and squash-merged branch were removed.


## 2026-08-19 16:34 — ProxyJump retired; pyinfra uses direct Tailscale SSH

Sandbox PR #2 (`refactor: use direct Tailscale transport`) merged as `f6ef9fe`. Routine deploy and hardening now target MagicDNS `sandbox01` with no SSH key or ProxyJump. The controller reads the online `tag:sandbox` peer from `tailscale status --json`, writes its coordination-server-advertised SSH host keys to a mode-0600 `.moon/cache` file, and gives that file to pyinfra with strict host-key checking. The obsolete tracked `ssh_config` was deleted. Explicit `--host 10.10.40.10 --known-hosts ~/.ssh/known_hosts` remains only for an unenrolled fresh-image bootstrap or break-glass path; the README documents temporarily disabling accepted subnet routes for that initial physical connection. Validation passed 27 tests, formatting, linting, typing, lock checks, CI, and the central docs build. A pyinfra dry-run, two complete deploys, and the hardening command all connected directly through MagicDNS; both deploys and hardening reported zero changes. The worktree and squash-merged branch were removed.


## 2026-08-19 16:44 — Close

Session 007 is complete. Six squash-merged PRs delivered the sandbox base and its required integrations: `GilmanLab/root` #16, `GilmanLab/networking` #9 and #10, `GilmanLab/secrets` #23, and `GilmanLab/sandbox` #1 and #2. Local `master` branches for all four repositories were fast-forwarded; the two remaining session implementation worktrees were removed. `sandbox01` is converged and hardened, both physical recovery and Tailscale SSH were verified, and routine pyinfra now uses direct MagicDNS transport with strict host-key checking. The live host was intentionally not reset. Session 002 can proceed with T32 on the validated but deliberately minimal Incus installation. See `SUMMARY.md` for the postmortem and full references.
