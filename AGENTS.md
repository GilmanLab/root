<!-- BEGIN ai-protocol -->
# Agent Instructions

This repository's operating protocol lives in `.session.md`.

Before doing substantive work, read `.session.md` in full and follow it. It
covers startup context loading, session setup, session lifecycle, skill loading,
Worktrunk branching, session journaling, file schemas, architecture, and process
expectations.

If `.session.md` is missing, stop and tell the user the session protocol is not
installed correctly.
<!-- END ai-protocol -->

## Sub-repository workflow

This is a meta repository. Directories cloned by `init.sh`, including `networking/` and `aws/`, are independent Git repositories. They are ignored here and are not submodules.

For work inside a sub-repository:

1. Treat the sub-repository as the repository root. Do not create its implementation branch or worktree from this meta repository.
2. Before editing, run `git fetch origin --prune` and `wt list --format=json` in the sub-repository.
3. Create a unique implementation branch and Worktrunk worktree from the fetched default branch. Use `wt switch --create --base origin/<default-branch> --no-cd --format=json <branch>` and work only in the returned path.
4. Run validation, commit, and push from that sub-repository worktree. Integrate through a GitHub pull request with squash merge unless the user explicitly requests a direct default-branch commit.
5. Do not use `wt merge`, `wt step push`, or local `git merge` as the default integration path. Remove the implementation worktree with `wt remove` after integration.
6. Never stage cloned sub-repository contents in this meta repository and never convert them to Git submodules.

## Documentation workflow

For documentation work in this meta repository or any cloned sub-repository,
read and follow `.agents/skills/gilmanlab-documentation/SKILL.md` from the meta
repository root. Its document classification, ownership rules, lifecycle, and
decision and design templates are required. Keep this skill canonical in the
meta repository; do not copy it into each sub-repository.

All GilmanLab documentation is centralized in this repository under `docs/`.
Sub-repositories must not create their own `docs/` trees; a documentation
change motivated by sub-repository work is a companion change in this
repository. When a sub-repository change alters behavior that is documented
here, update the affected documents in the same unit of work.

Build and verify the site with `moon run docs:build` before merging
documentation changes.
