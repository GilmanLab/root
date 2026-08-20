# NAS Bootstrap Plan — `fleet` repo + IncusOS on `nas01` (T30 + T42)

Status: ready for implementation. Drafted 2026-08-19 in session 002. The
implementing session reports back so session 002 closes T30/T42 on its report.

Self-contained. Context: `.journal/002/VISION.md` (bootstrap sequence,
seeding facts, secrets model), meta docs `reference/networking/address-plan.md`,
`designs/lab-v2-core-network.md`, ADR-0003.

## Goal

1. Create `GilmanLab/fleet` — the bare-metal instance-config repo (T26 charter:
   IncusOS seed configs + later Incus/OpenTofu runtime roots; NOTHING k8s).
2. Produce `nas01`'s seeded IncusOS install media with `incusos-builder`
   (built locally from source — release process still in flight product-side).
3. Install IncusOS on `nas01`, `incus remote add`, `incus cluster enable` —
   the lab's Incus cluster exists with one member.

End state: the lab can rebuild `nas01` from git + secrets + one USB stick.

## Non-goals

- lab01–03 (bootstrap step 2 — batch repeat later, gated on AMT/OOB).
- Talos VMs / critical services (step 3+, gated on T32 verdict).
- The 5x WD Red bay drives (T19) and any storage design beyond the default.
- Incus runtime config beyond what `apply_defaults: true` creates.
- CI image publishing (images are never published — local build+burn only).

## Facts

| Fact | Value |
| --- | --- |
| Host | `nas01` — Minisforum N5 Pro (Ryzen AI 9 HX PRO 370, 32GB) |
| Disks | 128GB NVMe (OS target) + 2x 1TB WD SN7100 NVMe (future pool; NOT the install target) |
| Network | mgmt `10.10.10.14/24` (DHCP reservation exists per address plan), gw `10.10.10.1`, VLAN 10 untagged via the 5GbE link → `sw-mgmt01` port 8 (PHY-019); 10GbE link → `sw-core01` port 7 (PHY-018) — leave unconfigured/no roles for now |
| No AMT | Delivery = USB stick (IMG/USB format — the ISO is non-hybrid and virtual-CD only). PiKVM MSD path untested (T01) — do not depend on it |
| Builder | `~/code/componere/incusos-builder` v0.1.0+, build from source (`mise install && mise x -- moon run root:build`); config = one YAML (image + seeds), SOPS-encrypted configs decrypt in memory (`-f file` or `-f -` stdin) |
| IncusOS requirements | UEFI Secure Boot + TPM 2.0 (T13 verifies); installer key enrollment can wipe vendor UEFI keys — retain Microsoft CA keys |
| Secrets | `GilmanLab/secrets`, `fleet` scope rule exists (empty); KMS `alias/glab-sops` + PGP encryption subkey `51098F038D5D9F84FE342036858A466C85A0979C!` per ADR-0003 |

## Design decision to encode: config/secret split

The builder takes ONE config document. `nas01`'s document contains both
non-secret config (network, install targeting, update policy) and secrets
(ZFS `encryption_recovery_keys`; the trust cert is public). Recommended split,
consistent with T26 + the secrets mandate:

- `GilmanLab/fleet` holds the **plaintext** builder config per node
  (`nodes/nas01/config.yaml`) with NO secret values — secret fields absent.
- `GilmanLab/secrets` holds the secret fragment under the `fleet` scope
  (`fleet/nas01/incusos.sops.yaml`: recovery key; plus `fleet/shared/`
  bootstrap-client material).
- A small render step in `fleet` (script or moon task) merges
  fragment + config and pipes the result to
  `incusos-builder build -f - -o nas01.img` — merged plaintext exists only
  in memory/pipe, never on disk. (Alternative if merging annoys: encrypt the
  *whole* per-node config into the secrets repo and point the builder at it —
  works natively, but puts non-secret machine config in the secrets repo;
  implementer may switch with a note if the merge proves clumsy.)
- Verify SOPS-KMS decryption works with the builder (docs demonstrate age;
  it's SOPS underneath, so KMS+`lab-admin` env should work — prove it early;
  fall back to `sops -d | incusos-builder -f -` which is equivalent).

## Phases

### Phase 0 — Physical verification (Josh, at the box; gates everything)

1. **T13**: BIOS — confirm TPM 2.0 present+enabled, UEFI Secure Boot
   supported+enabled. Record BIOS key-management state; prefer enrolling
   IncusOS keys alongside the Microsoft CA keys (NOT Setup-Mode wipe) — the
   NICs/option ROMs may need MS-signed firmware.
2. Confirm disk inventory as expected (128GB + 2x 1TB) — the seed targets the
   install disk by size (`target.max_size` ~ `200GiB` or
   `sort_order: smallest`); a surprise disk changes the config.
3. Confirm monitor/keyboard access for install day (console shows the IP and
   is the fallback if the seed misconfigures networking).

### Phase 1 — `GilmanLab/fleet` scaffold (T30)

1. Private repo, squash-only, org norms; wire into meta `init.sh`.
2. Layout: `nodes/nas01/config.yaml`, render script/task, README (charter:
   bare-metal instance config ONLY — no k8s, per T26; document the
   render-and-burn flow and the never-publish rule).
3. CI: `incusos-builder validate` against every node config with secret
   fields stubbed (validation must not need AWS) + lint. No publishing.
4. Pin the builder version used (record source commit until a release
   exists; re-pin on first release).

### Phase 2 — First fleet secrets

1. Generate the ZFS recovery key(s) → `fleet/nas01/incusos.sops.yaml`.
2. Bootstrap client: `incus remote get-client-certificate` (generates the
   operator client keypair if absent) — public cert goes into the fleet
   config (`incus.preseed.certificates`, name it per naming conventions);
   private key stays in the operator's Incus client config AND is escrowed at
   `fleet/shared/bootstrap-client.sops.yaml` (generated-durable exception).
3. Both files carry the `fleet` scope context + the PGP **encryption subkey**
   recipient; the secrets repo's metadata CI guard must pass.

### Phase 3 — nas01 config + media build

Config content (builder YAML; exact field names per builder
`reference/configuration.md`):

- image: `usb` format, `x86_64`, channel `stable`, pinned version (record
  it; `versions` lists releases).
- install seed: `target` = small NVMe (size-based selection); no
  `force_install` (fresh disk); `force_reboot: false`.
- applications: `incus`.
- incus seed: `apply_defaults: true` (this is the BOOTSTRAP node) + the
  trust certificate.
- network seed: hostname `nas01`, static `10.10.10.14/24`, gateway route,
  DNS `10.10.10.1`, interface bound by MAC (`strict_hwaddr: true`) to the
  **5GbE** NIC, roles `[management, cluster]`. Leave the 10GbE NIC without
  roles/addresses for now. NTP defaults.
- security seed: `encryption_recovery_keys` from the secrets fragment.
- update seed: channel `stable`, defaults otherwise.

Build + verify:

1. `incusos-builder validate` (stubbed), then full render → `validate -f -`,
   then `build -f - -o nas01.img`.
2. Write to USB (`dd` raw, whole device), verify written bytes if practical.

### Phase 4 — Install + cluster enable

1. Boot `nas01` from USB; installer runs; waits for media removal
   (`force_reboot: false`); remove stick; boots configured.
2. Confirm from console or ping: `10.10.10.14` reachable, hostname `nas01`.
3. `incus remote add nas01 10.10.10.14` — verify the server fingerprint
   against the console-displayed one (TOFU moment — do it deliberately).
4. `incus cluster enable nas01: <cluster-name>` (pick the cluster name
   consciously — it's permanent vocabulary; suggestion: keep it boring,
   e.g. `glab`).
5. Smoke: `incus cluster list`, `incus storage list` (local ZFS pool from
   defaults), launch/delete a test container, reboot `nas01` once and confirm
   it returns with config intact and the remote still trusts.

### Phase 5 — Documentation + report

1. Meta docs companion: this is the lab's first compute-platform reality —
   at minimum a runbook (`runbooks/` — rebuild-nas01 procedure) and an
   update to any architecture stub; a full compute architecture page can
   wait for lab01–03. `moon run docs:build` gates.
2. Report to session 002: deviations, pinned builder/IncusOS versions,
   whether SOPS-KMS decrypt worked natively, cluster name chosen, and
   verification table. Closes T30 + T42; T13 result recorded.

## Acceptance

- `fleet` repo exists, wired into `init.sh`, CI validates configs without AWS.
- Recovery key + bootstrap client escrow live in `fleet` scope, guard-passing.
- `nas01` boots from seeded USB with zero console interaction, reachable at
  `10.10.10.14`, hostname `nas01`.
- `incus remote add` + `cluster enable` succeed; default local pool present;
  test instance launches; survives one reboot.
- The whole flow is rerunnable from git + secrets + a blank USB stick.

## Risks

- **Secure Boot key enrollment wiping vendor keys** — retain MS CA keys
  (Phase 0 note); a bricked NIC option ROM on the NAS is a bad day.
- **Wrong install disk** — size-based `target` selection must be verified
  against Phase 0's disk inventory before writing the USB.
- **Recovery key custody before install** — the key must be committed to
  secrets (and pushed) BEFORE the encrypted pool exists; an install with an
  unescrowed key is a rollback trigger.
- **N5 Pro TPM/SB quirks** (consumer AMD platform) — if T13 fails, stop:
  degraded-security IncusOS modes are second-class; that becomes a
  Josh-decision, not an implementer workaround.
- **Console access is the only remote hand** — no AMT; if the seed's network
  config is wrong, it's monitor-and-keyboard time (or the untested PiKVM
  path). Double-check the MAC binding against the live NIC before build.
