# agentcompute phase prompts

One prompt per phase of `../PLAN.md`, written for a capable long-running
agent. Each prompt is self-contained: it restates the repository layout,
the documents to read, the working rules, and the acceptance evidence.
Feed one file per session; do not concatenate them.

| File | Phase | Blocks on |
| --- | --- | --- |
| `01-router-image.md` | Bootstrap `GilmanLab/agentcompute`; publish and consume one `router` image | nothing |
| `02-go-slice-1.md` | Go slice 1: containers + default bridge, real agent round trip | Phase 1 |
| `03-ovn-spike.md` | OVN mechanism spike (parallel with 2) | nothing |
| `04-lab-runners.md` | Image CI onto lab runners via incus-gh-runner v2.0.0 | Phases 1–2 |
| `05-durable-ovn.md` | Durable OVN + remaining `net.*` and lifecycle | Phases 2–3; the VLAN 40 decision |
| `06-linux-desktop.md` | Linux desktop image + `desktop.*` over exec | Phase 2 (+4 for capacity) |
| `07-windows.md` | Windows images + `net.impair` + router helpers | Phases 4–6 |
| `08-macos-lume.md` | macOS via Lume; second backend | Phase 6; the Mac host |
| `09-deploy.md` | Deploy as a cluster HTTP service; promote the draft | everything |

Documents every prompt refers to (absolute paths on Josh's workstation):

- Design draft (the contract): once the design PR is merged,
  `/Users/josh/code/lab2/docs/docs/designs/drafts/agentcompute.md`; until
  then the branch worktree
  `/Users/josh/code/lab2/.wt/feat-agentcompute-design/docs/docs/designs/drafts/agentcompute.md`.
- Session 019 artifacts, journal worktree
  `/Users/josh/code/lab2/.wt/journal-jmgilman/.journal/019/`:
  `PLAN.md`, `ARCHITECTURE_GO.md`, `IMAGE_PIPELINE.md`,
  `research/{linux,windows,macos}-images.md`, `NOTES.md`.
- Lab context: `/Users/josh/code/lab2/.wt/journal-jmgilman/.journal/TECH_NOTES.md`
  (stale on T48 — see `NOTES.md` 12:41), `/Users/josh/code/lab2/docs/docs/reference/networking/address-plan.md`,
  `/Users/josh/code/lab2/fleet/cluster/` (pyinfra project that owns all
  cluster configuration).

Prompts are advisory drafts. Adjust scope before feeding if earlier phases
changed the picture.
