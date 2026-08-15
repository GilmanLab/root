---
id: 001
title: Design Lab v2 core networking
started: 2026-08-14
---

## 2026-08-14 18:54 — Kickoff
Goal for the session: Design the Lab v2 core networking stack around VyOS and MikroTik infrastructure.
Current state of the world: The public GilmanLab/root repository is initialized on master, cloned to ~/code/lab2, and has the session protocol installed. The personal journal branch is ready.
Plan: Capture the next networking requirements, establish the core topology and configuration model, and proceed incrementally from the user's next request.

## 2026-08-14 19:01 — Meta repository bootstrap
Created the public GilmanLab/networking repository. Added a small idempotent root init script on feat/meta-networking-init that clones it over HTTPS into networking/, and updated .gitignore so the clone remains local. Verified script syntax, first-run cloning, repeat-run behavior, and ignore behavior. The implementation changes remain uncommitted pending user direction.

## 2026-08-14 19:06 — Meta repository bootstrap merged
Committed the init script and networking ignore rule as 81756b0, fast-forwarded master directly at the user's request, and pushed master to origin without opening a PR.

## 2026-08-14 19:38 — Branch cleanup and master clone
Removed the feat/meta-networking-init worktree and branch, leaving only master and the journal worktree. Ran ./init.sh in the master checkout, which cloned the empty GilmanLab/networking repository into networking/ and confirmed the path stays ignored. Note: the clone's remote resolved to git@github.com despite the HTTPS URL in the script, so a global Git url.insteadOf rewrite is in effect on this machine.

## 2026-08-14 19:42 — Switch init clone to SSH
Changed init.sh to clone git@github.com:GilmanLab/networking.git instead of the HTTPS URL, so the remote no longer depends on the machine-local url.insteadOf rewrite. Committed directly to master as 9f061a4 and pushed. The existing networking/ clone already points at the SSH remote, so no re-clone was needed.

## 2026-08-14 20:04 — Initialize networking repository toolchain
Initialized GilmanLab/networking directly on master because the repository had no base commit. Added mise with pinned Python 3.14.7, uv 0.12.3, and moon 2.4.6 plus a four-platform mise.lock; a Moon workspace with a docs project; a uv-locked Material for MkDocs site; and a SHA-pinned GitHub Pages workflow. Local `moon run docs:build --summary minimal` completed successfully with MkDocs strict mode. Pushed commits 81affcf and 1bee0c7, set master as the default branch, enabled Pages with Actions, and verified workflow run 31835827669 built and deployed successfully. GitHub reports the inherited Pages URL as http://docs.gilman.io/networking/, and gilmanlab.github.io redirects there, but docs.gilman.io currently has no resolvable DNS record; the deployment exists but the public endpoint is not reachable until DNS is restored.

## 2026-08-14 20:23 — Enforce sub-repository Worktrunk flow
Confirmed the networking bootstrap was already committed and pushed on networking/master. Added a project-owned AGENTS.md section outside the framework markers that treats cloned children as independent repositories, requires fetch plus `wt list`, creates child-local implementation worktrees from the fetched default branch, requires validation and GitHub squash PR integration by default, prohibits local merge shortcuts, and preserves the no-submodule boundary. Committed on docs/subrepo-worktrunks, opened root PR #1, squash-merged it as 17c5c33, fast-forwarded local master, and removed the implementation worktree.

## 2026-08-14 22:14 — Standardize repository-local documentation
Added the tracked root-local `gilmanlab-documentation` skill and made it mandatory from `AGENTS.md`. The contract keeps documentation in its owning sub-repository and classifies content under architecture, decisions, designs/drafts, reference, and runbooks. It adopts Diátaxis for purpose, MADR 4.0 for decisions, a lightweight Google-style design-doc funnel, optional KEP production-readiness prompts, and selective arc42 architecture views. Added reusable MADR decision and design templates. Validated skill discovery and template contracts, squash-merged root PR #2 as 3bcd8c0, fast-forwarded local master, and removed the implementation worktree.

## 2026-08-14 23:37 — Add initial networking documentation
Applied the repository documentation convention in GilmanLab/networking. Added accepted ADR-0001 for the VyOS Layer 3 and MikroTik Layer 2 responsibility split, a draft Lab v2 core-network design that keeps addresses and port assignments unresolved pending evidence, and a hardware reference that separates legacy repository evidence from required physical verification. Updated the landing page and MkDocs navigation; deliberately omitted architecture and runbook directories until implementation and proven procedures exist. MkDocs strict build passed, prose-trigger review found no flagged language or excluded platform names, browser checks exercised the home, design, ADR, and hardware pages, and the PR build check passed. Squash-merged networking PR #1 as d290763 and removed the implementation worktree.

## 2026-08-14 23:47 — Make networking documentation authoritative
Removed all Lab v1, legacy-source, evidence-status, provisional port-map, candidate address-plan, and open-question prose from the networking documentation. Narrowed the draft to direct Lab v2 topology, device boundaries, routing/NAT invariants, configuration requirements, failure boundaries, and behavioral verification. Replaced the hardware evidence ledger with an authoritative device-role reference and removed unsupported management-path detail. Searches found no remaining historical references or uncertainty-language triggers. MkDocs strict build passed; browser checks covered all four pages and rejected forbidden historical terms; PR checks and Pages deployment passed. Squash-merged networking PR #2 as aa131b4 and removed the implementation worktree.

## 2026-08-15 00:10 — Record authoritative switch topology
Confirmed the lab switch is a MikroTik CRS309-1G-8S+IN. Added the TRENDnet TEG-3102WS, its direct uplink to the VP6630, and both non-SFP MS-02 NICs as management/OOB links. Explicitly verified with the user that VyOS provides the Layer 3 gateway and firewall policy for that management/OOB network. Updated hardware reference, design topology, device responsibilities, routing invariants, traffic policy, failure boundaries, verification checks, navigation, and ADR-0001. Renamed ADR-0001 to cover dedicated Layer 2 switches and migrated all links. MkDocs strict build, browser checks, PR checks, and Pages deployment passed. Squash-merged networking PR #3 as 39af79a and removed the implementation worktree.
