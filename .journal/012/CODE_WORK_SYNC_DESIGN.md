# Design: syncing ~/code and ~/work between the workstations

Status: **proposal — nothing configured.** Prepared 2026-08-22, after Josh's
purge pass and after the omp/skills work landed.

## Measured state

| | MacBook | Studio |
|---|---|---|
| `~/code` | 59 GB | 46 GB |
| `~/work` | 97 GB | 123 GB |

MacBook composition:

| Root | Repos | `.wt` worktrees | `.git` total | Largest disposable |
|---|---|---|---|---|
| `~/code` | 93 | **59** | 4.7 GB | `target` 15.3 GB, `node_modules` 8.1 GB (290 dirs), `build` 5.7 GB, `.venv` 3.1 GB, `dist` 1.4 GB |
| `~/work` | 9 | 4 | **12.4 GB** | `.terraform` 11.2 GB (16 dirs), `.venv` 1.2 GB |

So of ~156 GB, roughly **46 GB is reproducible junk** and **17 GB is `.git`**.
The genuinely irreplaceable part — uncommitted working-tree edits — is a small
fraction of the total.

## The three hazards, ranked

**1. Worktrunk worktrees will break. 59 of them in `~/code`.**
Each `.wt/<branch>/.git` is a *file* containing
`gitdir: /Users/josh/code/<repo>/.git/worktrees/<name>`, and the parent repo
records the worktree's absolute path in `.git/worktrees/<name>/gitdir`. Both
paths are `/Users/josh/...` on both machines, so they resolve — but the two
sides then disagree about which worktrees exist, `git worktree prune` on one
machine deletes administrative files the other still references, and a
half-synced pair yields "fatal: not a git repository" or a worktree git believes
is registered twice. **Recommendation: exclude `.wt/` outright.** Worktrees are
per-machine scratch by design; that is the whole premise of the Worktrunk
workflow.

**2. `.git` under file-level sync is safe only while exactly one machine
writes.** Git is not transactional across files: `index`, `refs/`, and
`objects/` are updated in sequence. Syncthing transfers whole files atomically,
so the receiving side never sees a half-written file, but it can absolutely see
a *half-written set* — a new packfile without its updated ref, or an index
referencing objects that have not landed. Concurrent writes produce
`.sync-conflict` copies inside `.git`, which git does not understand.
Recovery is real but manual: `git fsck`, `git reset`, or re-clone. The remote is
always the source of truth, so nothing is unrecoverable — it is downtime, not
data loss.

**3. Volume and churn.** `node_modules` alone is 290 directories and 8.1 GB of
tiny files, which is the worst possible Syncthing workload: hashing cost is
per-file, not per-byte. The initial `omp-sessions` pass ran at ~560 KB/s on
7,271 files. Left unfiltered, `~/code` plus `~/work` is a multi-day scan.

## Proposed shape

Two folders, aggressive ignores, versioning on.

```
folder  code   ->  ~/code
folder  work   ->  ~/work
type    sendreceive both sides
versioning  staggered, maxAge 30d
fsWatcherEnabled  true, delay 30s
```

Ignore file (identical for both folders):

```
// machine-local worktrees — never sync
(?d).wt

// build outputs and dependency trees
(?d)node_modules
(?d)target
(?d)dist
(?d)build
(?d).next
(?d).turbo
(?d).parcel-cache

// language caches and virtualenvs
(?d).venv
(?d)venv
(?d)__pycache__
(?d).pytest_cache
(?d).mypy_cache
(?d).ruff_cache
(?d).tox
(?d).gradle
(?d).m2

// infra state and provider mirrors
(?d).terraform
(?d).terragrunt-cache

// nix and direnv
(?d).direnv
(?d)result
(?d)result-*

// editor and OS noise
(?d).DS_Store
(?d).idea
(?d).vscode/chrome-debug-*

// large local artifacts
(?d)*.tar
(?d)*.tar.gz
(?d)*.dmg
(?d)*.qcow2
(?d)*.img
```

`(?d)` lets Syncthing delete an ignored item when it is removing the containing
directory, which avoids stuck deletes.

Estimated result: **~59 GB → ~25 GB** for `~/code` and **~97 GB → ~84 GB** for
`~/work` (the `.terraform` and `.venv` cuts), with the file *count* down by far
more than the byte count — which is what actually determines sync speed.

## Open decision: `.git` in or out?

**In (recommended).** Syncing `.git` is what makes uncommitted work,
stashes, and local branches follow you — the actual goal. Accept the
one-writer-at-a-time discipline, keep staggered versioning as the undo, and
treat corruption as a re-clone rather than a catastrophe.

**Out.** Excluding `.git` leaves working trees without repositories: `git
status` fails, and the receiving machine cannot do anything useful. Only
coherent if the intent is "mirror the files, clone separately", which defeats
the purpose.

## Sequencing

1. Land Phase 3 and the omp purge first. Do not add a multi-day scan while MCP
   consolidation is still being verified.
2. Reconcile the two sides **before** peering: the Studio's `~/work` is 26 GB
   larger and its `~/code` is 13 GB smaller. First sync would union them,
   resurrecting anything deleted on one side only. Decide per-root which machine
   is authoritative, or diff the trees first.
3. Start with `~/code` alone. It is smaller, its content is lower-stakes, and it
   exercises every hazard (93 repos, 59 worktrees).
4. Watch for `.sync-conflict` files under any `.git` directory for a week. Their
   presence means the one-writer discipline is not holding, and the design needs
   revisiting.
5. Only then add `~/work`.

## Note on agent-skills

`~/code/agent-skills` is now load-bearing: `~/.agents/skills` symlinks to it. If
`~/code` is synced, that checkout is synced too — which finally makes skills
parity automatic rather than a `git pull`. It also means a `.git` corruption
there degrades skill discovery. Consider excluding `agent-skills` from the
`code` folder and keeping it on `git pull`, precisely because it is now
infrastructure rather than scratch.
