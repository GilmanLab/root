---
id: 009
title: Session opened, goal pending
started: 2026-08-20
---

## 2026-08-20 20:03 — Kickoff
Goal for the session: not yet stated. The user asked only to create a new
session; the actual request will follow and will be appended here.
Current state of the world:
- Journal root is the `journal/jmgilman` worktree at `.wt/journal-jmgilman`
  (clean, in sync with origin). Sessions 001-008 are all closed.
- Loaded startup context: `SKILLS.md` (`git`, `worktrunk` — both loaded),
  `TECH_NOTES.md`, and summaries for 006, 007, 008.
- Lab state per 008: `gw01` (VyOS) owns L3/DHCP/DNS/firewall/NAT/Tailscale
  routing; `sw-core01` is OpenTofu-managed with an empty plan; `sw-mgmt01` is
  hand-managed at `10.10.70.2` with an escrowed backup; `nas01` runs IncusOS as
  the first Incus cluster member with both SN7100 drives still blank pending a
  storage design; `sandbox01` is converged via `GilmanLab/sandbox` pyinfra.
- Open threads carried in from 008: rotate `sw-core01` `admin` and `svc-tofu`
  passwords, rule on the leftover v1 CA certs, upstream the
  `routeros_ip_service` import defect, migrate the pinned self-signed CA when a
  device PKI intermediate exists, test the TEG-3102WS `cfg_upload` restore path,
  and re-add the gw01 `eth3` escape hatch if factory switch access is needed.
- `.journal/VISION.md` holds the running T-item tracker; consult it once the
  goal is known.
Plan: wait for the user's actual request, then scope work against
`.journal/VISION.md` and create implementation worktrees in the appropriate
repository per the sub-repository workflow.

## 2026-08-21 11:49 — Goal set: bring lab01–03 online
Josh chose bootstrap step 2 for this session: configure the OOB links on the
lab nodes and install IncusOS on `lab01`–`lab03`, joining them to the `nas01`
cluster (VISION step 2; touches T01/T03/T06/T12). NAS storage (T19 + NAS-OS
design) deliberately deferred to a later session; clarified that the Synology
drives are already backed up to a large external HDD, so only
install/wipe remains.
Operations Center ruling: do NOT set up OC before the node joins. Evidence:
IncusOS provider is runtime-modifiable (`SystemProviderConfig` documented as
the modifiable part, `Registered` state flag), so post-install registration
with a future OC needs no reinstall; OC's documented flow only provisions
clusters from freshly seeded self-registered servers (adopting an existing
cluster is undocumented, and nas01 pre-exists OC under any ordering); OC wants
to own seeding/updates, colliding with decided fleet + incusos-builder model
(T25/T26/T30); OC is young (announced 2025-12-21, v0.81). Plan: OC becomes a
follow-up spike on `sandbox01` or a cluster VM — verify late registration +
existing-cluster visibility empirically. Add a tracker item at close.
Next: inventory the lab-node hardware facts (AMT state, NIC MACs, cabling)
and drive the proven seeded-install procedure per `rebuild-nas01.md`,
adapted for lab01–03.
