# Technical Notes

## Vision and tracker

- `.journal/VISION.md` (journal root, beside this file) is the living Lab v2
  vision-and-context document with the running work Tracker (T-items). Read it
  before substantive lab work and keep its statuses current. Confidence tags:
  [DECIDED]/[PROVISIONAL]/[OPEN]. Handoff plans it references live in
  `.journal/002/`.

## Compute platform (four-node cluster live)

- The Incus cluster is four IncusOS nodes (all release-pinned together,
  installed from `GilmanLab/fleet` `nodes/<name>/config.yaml`): `nas01`
  `10.10.10.14` (database-leader), `lab01` `.11` + `lab02` `.12` (database
  voters), `lab03` `.13` (database-standby). Operator access uses the seeded
  `bootstrap-admin` client cert (private half escrowed at
  `fleet/shared/bootstrap-client` in `GilmanLab/secrets`).
- Commissioning a lab node is runbooked end to end:
  `docs/docs/runbooks/commission-lab-node.md` (session 009) — MEBx/AMT,
  the AMI "Factory Key Provision" Secure Boot recipe, MAC harvest
  (mgmt MAC = AMT MAC + 1 on the MS-02s, but always verify), USB install,
  rescue wipe for old-OS remnants, fingerprint check, key escrow + the
  `:retrieved` acknowledgment, API join with `local/incus` member config.
- Lab-node OOB is AMT (TLS-only: 16993/16995; consent NONE): static MEBx
  addresses `10.10.70.11–13`, credentials at `fleet/lab0N/amt.sops.yaml`.
  AMT clients MUST sit on VLAN 10 (gw01 drops AMT ports on home→OOB);
  the credential-less `meshcommander` container on nas01
  (`http://10.10.10.14:3000/`) is the standing gateway (disposition: T47).
  AMT IDER/USB-R boot is BANNED on the MS-02s — it wedges AMI 2.22.0059
  pre-boot; install media stays USB.
- Per-node recovery material is escrowed at `fleet/<name>/incusos.sops.yaml`
  (LUKS recovery key + `local` ZFS pool key), captured before each join.
  nas01 rebuild procedure: `docs/docs/runbooks/rebuild-nas01.md` — clear the
  fTPM on previously-used hardware, never write install media to an internal
  drive, never install through Ventoy, escrow recovery keys before any
  reboot test.
- Private `GilmanLab/fleet` holds bare-metal instance config (no k8s):
  day-0 seeds (`nodes/<name>/config.yaml`) AND day-2 cluster convergence —
  the `cluster/` pyinfra project (session 010) owns storage pools and the
  fast/storage network via `CI= moon run fleet-cluster:storage|network`
  (@local connector, authenticated `nas01:` remote required; ALL cluster
  config flows through it, no ad-hoc commands). Deploys assert the
  recovery-key `:retrieved` flag: convergence fails until keys are
  escrowed + acked (escrow itself stays a runbook step). Seeds mirror
  runtime network state for reinstalls. Install images are built locally
  with componere's `incusos-builder` (pin in the fleet README) and never
  published; fleet CI validates seeds with the pinned builder + runs the
  cluster project checks.
- Storage (session 010): every node has an encrypted `data` zpool (nas01 =
  mirror of the 2x 1TB SN7100s, ~928GB; labs = single 2TB 990 EVO) backing
  the cluster-wide Incus pool `data` (`source=data/incus`). nas01 also has
  `hdd` (zfs-raidz1, 4x 6TB WD Red Pro, 17.4TB usable) — OS-level only:
  nas01-only Incus cluster pools are unsupported; Incus wiring waits for
  the object-storage design (T16). 5th-drive expansion = device append
  (raidz expansion, one device per resilver). Pool recovery keys:
  `fleet/<node>/incusos.sops.yaml` (`zfs_pool_<name>_recovery_key`).
  CAUTION: `:wipe-drive` full-zeroes TRIM-less HDDs (~9h/6TB) synchronously;
  duplicate wipe POSTs queue behind a storage lock and survive client
  disconnects (the same lock wedges `:reboot`) — check `debug/processes`
  before re-POSTing. nas01 N5 Pro bays hot-swap cleanly.
- Storage network VLAN 30 (`10.10.30.0/24`, L2-only, no gateway, not on the
  gw01 trunk): nodes have `fast`/`fast30` (labs = active-backup bond over
  the SFP+ pair — LACP is non-viable, see T48; nas01 = plain 10GbE) with
  addresses mirroring mgmt last octets. `vlan_tags` on the fast parent is
  REQUIRED (IncusOS interfaces are internal VLAN-filtering bridges).
  Incus cluster raft/API deliberately stays on VLAN 10 (address move =
  offline all-member edit; bulk traffic rides instance VLANs later).
  T48 BLOCKER: lab datapath dead switch→host — IncusOS ships no ice DDP
  (E810 Safe Mode) and the 25G DACs at 10G mis-negotiate FEC. Upstream fix
  MERGED (lxc/incus-os#1306); 6x 10G DACs arrive ~2026-08-24. Retest:
  cross-node macvlan pings on fast30, then deploy reruns.
- nas01 NICs: `38:05:25:37:8d:7a` = RTL8126A 5GbE → `sw-mgmt01` port 8
  (mgmt, links 2.5G, MAC-bound in the seed); `38:05:25:37:8d:7b` = RTL8127A
  10GbE `fast` → `sw-core01` port 7 (10G optic — the proven link pattern).
  Lab-node mgmt NICs (10GbE, MAC-bound): lab01 `38:05:25:35:48:87`, lab02
  `…:4b:05`, lab03 `…:43:f1`; lab SFP+ pairs (E810-XXV) → sw-core01
  ports 1–6, VLAN 30 tagged.
- `sw-mgmt01` (TRENDnet TEG-3102WS, IMG-3.01.347) is fully configured per the
  address plan: static mgmt `10.10.70.2/24` on VLAN 70 (gw 10.10.70.1), VLAN
  10 tagged trunk port 1 + untagged 2/4/6/8, VLAN 70 untagged 3/5/7, VLAN 1
  trimmed to unused SFP slots, PVIDs match; saved config escrowed at
  `network/sw-mgmt01/config-backup.sops.yaml`. Hand-managed appliance: web UI
  + JSON API over plain HTTP (runbook `sw-mgmt01-configuration.md` documents
  the API and its silent-no-op write hazard — always read back writes). Admin
  credential: `network/sw-mgmt01/admin.sops.yaml`. Factory access requires a
  temporary gw01 `eth3 192.168.10.5/24` address (runbook).
- PiKVM (`https://10.10.70.20/`): console snapshots (`/api/streamer/snapshot`)
  and HID injection work through the TESmart and can drive full installs.
  Mass-storage emulation through the TESmart does NOT work (USB 1.1), and
  HID-injected TESmart hotkeys do NOT switch channels (PiKVM sits on a
  pass-through hub port — re-plug or RS232 to fix). Web creds are still
  default admin/admin (T45). The ATX header is not wired — power cycles are
  physical or via AMT on the lab nodes.

## Repository layout

- `GilmanLab/root` is a meta repository. `init.sh` clones
  `GilmanLab/networking`, private `GilmanLab/aws`, and private
  `GilmanLab/sandbox` as ignored independent repositories, not submodules.
- Sub-repository changes use a branch and Worktrunk created inside that child
  repository, followed by a GitHub squash-merge PR.
- The canonical documentation skill is
  `.agents/skills/gilmanlab-documentation/SKILL.md` in the root repository.

## AWS substrate

- Private `GilmanLab/aws` is the sole writer for six OpenTofu roots:
  `aws/lab-foundation`, `aws/github-oidc`, `network/tailscale`,
  `security/pki/root-ca`, `aws/subnet-router`, and `aws/keycloak`.
  `GilmanLab/infra` no longer contains or writes these roots.
- The lab account is `186067932323` in `us-west-2`, operated with profile
  `lab-admin`. Its manually bootstrapped state bucket is
  `glab-lab-tfstate-186067932323`; state keys remained stable through the move.
- Identity-critical resources include SOPS KMS key
  `2aba1d94-6eaf-4d80-8d26-2077f32fd7c5`, root-CA KMS key
  `5b585512-8604-43ce-b416-90fbd3cffcfa`, private zone
  `Z009084217D5KKVQERJY3`, subnet router `i-07878bb4aa9896dd4`, and Keycloak
  instance `i-069f5e943c6e11092` with volume `vol-09baa3d716d956887`.
- The old-account `s3://gilmanlab-tfstate/network/tailscale.tfstate` remains
  only for the migration rollback window. Delete it explicitly afterward, but
  never read, copy, or delete that bucket's similarly named
  `security/pki/root-ca.tfstate`, which belongs to a destroyed old key.
- Keycloak stays live until Zitadel serves. Its normal OpenTofu plan is clean;
  a refresh-only plan observes provider-computed EBS attachment metadata and
  should not be applied merely to silence migration drift.

## Secrets root of trust

- Private `GilmanLab/secrets` uses one SOPS key group per file containing
  scoped AWS KMS and YubiKey-backed PGP as alternative recipients. Routine
  access uses KMS key `2aba1d94-6eaf-4d80-8d26-2077f32fd7c5`; break-glass
  recovery uses exact Curve25519 encryption subkey
  `51098F038D5D9F84FE342036858A466C85A0979C!` from primary identity
  `3965F16E293466CFE77D47F38C15553EEB22DB2A`.
- Every KMS recipient requires encryption context `Repo: GilmanLab/secrets`
  plus `Scope: <access-boundary>`. An unconditioned consumer grant spans every
  scope and is a defect. Future IAM roles belong in `GilmanLab/aws` and are
  created only for real workflows.
- Secret domains are `fleet/<node>/`, future `clusters/<name>/`,
  `services/<service>/`, and `network/`; legacy `compute/` remains frozen.
  Generated but durable recovery material belongs in the encrypted repository;
  ephemeral runtime-generated secrets do not.
- `GilmanLab/secrets/scripts/check_sops_metadata.py` validates recipients and
  encryption context in CI without decryption. PGP recovery must still be
  tested periodically with a YubiKey and AWS credentials absent.

## Network authority

- The VP6630 `gw01` runs VyOS and owns Layer 3 gateways, static routing,
  firewall policy, NAT, DHCP, CoreDNS, and Tailscale subnet routing.
- The accepted routed VLANs are management VLAN 10 (`10.10.10.0/24`),
  sandbox/workload VLAN 40 (`10.10.40.0/24`), and OOB VLAN 70
  (`10.10.70.0/24`). VLAN 20 and BGP are retired.
- The former UM760 cluster node is `sandbox01` on VP6630 `eth3`, untagged VLAN
  40, with DHCP reservation `10.10.40.10`.
- `sw-core01` (MikroTik CRS309, RouterOS 7.24 since session 010, static
  `10.10.10.2` on VLAN
  10) carries core Layer 2 VLAN traffic and is OpenTofu-managed: root
  `routeros/sw-core01/` in `GilmanLab/networking`, state key
  `networking/routeros/sw-core01.tfstate` in the lab bucket, REST over
  `www-ssl` pinned to the committed device-local CA, creds via SOPS →
  `ROS_*` env (`network/sw-core01/terraform.sops.yaml`). Mgmt-path resources
  are adopt-only; users/groups/certs are runbook-owned (`svc-tofu` lacks the
  `policy` permission by design). RouterOS quirks: REST needs the `api`
  policy; leaf certs cannot self-sign (device-local CA); REST rejects
  percent-encoded `*`; `routeros_ip_service` import is broken upstream
  (adopt-by-create). Runbook: `sw-core01-configuration.md`, ADR-0004.
- The TRENDnet TEG-3102WS (`sw-mgmt01`) connects both non-SFP NICs from each
  MS-02 for management/OOB and uplinks directly to the VP6630.
- The MikroTik CCR2004 connects the lab to the home network and internet over
  `10.0.0.0/30`; `gw01` is `10.0.0.2` and uses `10.0.0.1` as its default route.
- The CCR2004's physical `10.10.0.0/16 via 10.0.0.2` route uses an ICMP
  health check. `gw01` must allow ICMP from transit-router address `10.0.0.1`;
  otherwise RouterOS marks the route inactive and silently uses its internet
  default route for lab destinations.
- `gw01` serves NTP (chrony, synced to time.cloudflare.com); its input
  firewall admits UDP 123 only from VLANs 10 and 70 (`MGMT_LOCAL`,
  `OOB_LOCAL`). VLAN 70 has no internet path, so gw01 is its only time
  source. `sw-core01` syncs to `10.10.10.1`.
- `docs/docs/reference/networking/physical-connections.md` is the authoritative
  port-to-port map. `docs/docs/reference/networking/address-plan.md` owns
  prefixes, VLANs, DHCP reservations, and logical port roles.
- `GilmanLab/networking/vyos/gw01/config.boot.tmpl` and its CoreDNS assets are
  the gateway source. `networking_vyos sync` performs a secret-free full load,
  applies the console hash separately, verifies live behavior, then saves.
- The rolling VyOS 2025.11 image needs empty nftables compatibility chains
  before interface commit hooks. Failed commits can leave runtime side effects
  and `PendingSave=True`; reboot to the saved config before retrying.
- Moon excludes `runInCI: false` tasks from `moon run` when the `CI` env var
  is truthy (agent shells export `CI=true`): operator tasks need
  `CI= moon run network:vyos-facts` (noted in the vyos runbook).
- Do not import historical or unverified values into authoritative documents.
  Ask the user to verify missing facts or omit them.

## Sandbox host

- Private `GilmanLab/sandbox` owns reset-button pyinfra automation for Ubuntu
  26.04 host `sandbox01` (`10.10.40.10`, VLAN 40). Routine deploys target
  MagicDNS `sandbox01`; explicit physical host and known-hosts overrides are
  only for unenrolled bootstrap or break-glass access.
- The controller mints a single-use, preauthorized, non-ephemeral Tailscale key
  with a 10-minute TTL from the scoped OAuth client in
  `GilmanLab/secrets/sandbox/tailscale.sops.yaml`, and only when enrollment is
  required. Runtime key material lives under root-only `/run` and is shredded.
- Routine SSH host verification uses the online `tag:sandbox` peer keys from
  `tailscale status --json`, written to a mode-0600 cache file. Do not restore
  ProxyJump or disable strict host-key checking.
- sshd hardening is a separate final command. The managed effective policy
  disables password and root login, permits `josh`, and keeps Tailscale SSH and
  explicit physical recovery available.
- Incus intentionally uses one 50 GiB loop-backed ZFS pool and the default
  bridge. There is no cluster, project taxonomy, monitoring, backup policy, or
  approved durable workload yet.

## Documentation tooling

- The meta repository hosts the only MkDocs site, at `docs/`, with a strict
  build. Run `mise exec -- moon run docs:build --summary minimal`. The
  networking repository no longer has a docs tree; an untracked leftover
  `docs/` directory may still sit in its checkout.
- GitHub Pages deploys from `.github/workflows/docs-pages.yml`.
- GitHub Pages deployments succeed, but `docs.gilman.io` did not resolve during
  session 001.

## Tailscale policy

- The tailnet policy file is version controlled at
  `GilmanLab/networking/tailscale/policy.hujson` and applied by
  `.github/workflows/tailscale-acl.yml`: `test` on pull requests, `apply` on
  push to `master` and manual dispatch. Never edit the policy in the admin
  console; the next apply overwrites it.
- `tag:sandbox` is owned by `autogroup:admin`; the policy authorizes the
  intended `josh`, `sandbox`, and `root` Tailscale SSH paths to sandbox hosts.
- Tailnet ID `THZctfF8wr11CNTRL`. The workflow reads repository *variables*
  `TS_TAILNET`, `TS_POLICY_CLIENT_ID`, and `TS_POLICY_AUDIENCE`; none is secret.
- CI authenticates with a Tailscale OIDC trust credential (workload identity
  federation), scopes `policy_file` plus `devices:posture_attributes` and
  `devices:core:read`. No long-lived Tailscale credential exists in CI.
- GitHub issues immutable OIDC subjects for this organization, for example
  `repo:GilmanLab@66194346/networking@1334494603:ref:refs/heads/master`. Trust
  credential subjects must use that numeric form; a name-based pattern fails the
  token exchange with HTTP 403.
- `gitops-pusher` drift detection is inert in ephemeral CI because its
  `--cache-file` etag cache is never persisted. The admin-console lock is the
  real control.
- The SOPS-encrypted node-registration OAuth client in
  `GilmanLab/secrets/network/vyos/tailscale.sops.yaml` must not be reused for
  policy work. It is no longer present in `gw01` configuration or required by
  gateway automation. Treat it as exposed and revoke it.
