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
