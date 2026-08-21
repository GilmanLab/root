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
