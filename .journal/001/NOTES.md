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
