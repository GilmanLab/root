# Plan: consolidate MCP + skills into omp, purge the other CLI configs

Status: **proposal for review — nothing executed.**
Prepared 2026-08-22.

## Constraint that shapes everything

Josh still launches Cursor agents through Paseo (`cursor-agent acp`), so
`~/.cursor/` stays. Everything else (`~/.claude*`, `~/.codex`, `~/.gemini`) is
disposable once its content is migrated.

omp *imports* other tools' MCP configs. That means today's working tool set is
produced by the union of five files, and deleting any of them silently removes
tools. Migration must therefore be: **declare in omp → prove parity → disable
imports → delete**, in that order.

## Current MCP inventory (union of all sources)

| Server | Transport | Command / URL | Sources today | Keep? |
|---|---|---|---|---|
| `browserless` | http | `mcp.browserless.io/mcp` | omp | yes |
| `cloudflare-api` | http | `mcp.cloudflare.com/mcp` | omp | yes |
| `context7` | http | `mcp.context7.com/mcp` | codex, claude, cursor | yes |
| `agentmail` | http | `mcp.agentmail.to/mcp` | codex, claude | yes |
| `transcriptapi` | http | `transcriptapi.com/mcp` | claude | decide |
| `gitnexus` | stdio | `gitnexus mcp` | omp | yes |
| `bitwarden` | stdio | `bw-mcp` | omp, codex, claude | yes |
| `1password` | stdio | `/Applications/1Password.app/…/1password-mcp` | omp, codex, claude | yes |
| `adrafinil` | stdio | `/Applications/Adrafinil.app/Contents/Helpers/adrafinil mcp` | claude | yes (cask-declared) |
| `pencil` | stdio | `/Applications/Pencil.app/…/mcp-server-darwin-arm64` | claude, gemini | decide — app is **not** a declared cask |
| `exa` | stdio | `npx -y exa-mcp-server` | codex, claude, cursor | yes → switch to `bunx` |
| `chrome-devtools` | stdio | `npx chrome-devtools-mcp@latest` | codex, claude, cursor, gemini | yes → switch to `bunx`, pin version |
| `git` | stdio | `uvx mcp-server-git` | cursor | decide — `uv` is nix-managed, fine |
| `github` | stdio | `docker run … ghcr.io/github/github-mcp-server` | cursor | decide — needs Docker + PAT |
| `node_repl` | stdio | inside `ChatGPT.app` | codex | **drop** — already in omp `disabledServers` |
| `computer-use` | stdio | *relative* path into `Codex Computer Use.app` | codex | **drop** — Codex-only, relative path cannot work elsewhere |
| `excalidraw`, `adk-docs`, `grafana-demo`, `time` | mixed | per-project in `.claude.json` | claude | **drop** unless named |

Also in `~/.cursor/mcp.json`: a **malformed `mcpServers` key nested inside
`mcpServers`**. It is junk and should be deleted regardless of this plan.

## Phase 1 — make every kept server portable (no deletions)

1. Replace `npx` with `bunx` for `exa` and `chrome-devtools`. `bun` is
   nix-managed and identical on both machines; `npx` resolves through nodenv on
   the MacBook and Homebrew on the Studio.
2. Pin `chrome-devtools-mcp` instead of `@latest`, so both machines run the
   same server build.
3. Confirm each stdio binary exists on **both** machines before declaring it.
   Known gaps: `Pencil.app` is installed on neither as a declared cask;
   `github` needs Docker plus `GITHUB_PERSONAL_ACCESS_TOKEN`.
4. Secrets stay out of the file: use `${VAR}` expansion or `!command`
   indirection (e.g. `!op read op://…`), which omp resolves at connect time.

## Phase 2 — declare everything in omp

Write the full set into `~/.omp/agent/mcp.json` on both machines. It currently
holds 5 servers; the target is roughly 12.

Verification gate: `/mcp list` shows every expected server, and
`/mcp test <name>` passes for each stdio server, **on both machines**.

## Phase 3 — turn off the imports, without deleting anything

Set the source toggles in omp settings: `enableClaudeUser`, `enableCodexUser`,
`enableAgentsUser`-family flags, and disable Cursor/Gemini/VS Code discovery.
This is fully reversible.

Verification gate: re-run `/mcp list`. The set must be **identical** to
Phase 2. Any server that disappears was still being supplied by an import and
is not yet migrated.

Cursor keeps reading its own `~/.cursor/mcp.json` for `cursor-agent`; omp just
stops importing it. That means Cursor's MCP set is deliberately allowed to
diverge from omp's.

## Phase 4 — skills

Source of truth is `~/code/agent-skills` (`meigma/agent-skills`).

1. Diff the three copies first — `~/.claude/skills` (27) and `~/.codex/skills`
   (29) have **already diverged**: `cli/SKILL.md` differs. Reconcile into the
   repo before deleting either copy.
2. Decide on `~/.codex/skills/.system/` — 6 vendor skills (`skill-creator`,
   `review-agent`, `imagegen`, `openai-docs`, `plugin-creator`,
   `skill-installer`) that are not yours and are not in the repo. Keep by
   copying into the repo, or drop deliberately.
3. Render `~/.agents/skills/<name>/SKILL.md` from the repo via home-manager
   (symlinks are fine here — unlike `authorized_keys`, nothing validates
   ownership). Directory does not exist yet, so it is a clean target.
4. Keep repo-local `.agents/skills` as-is: project scope already works and is
   version-controlled with each repo.

Verification gate: omp's skill list matches today's, with no duplicate-name
collisions in the logs.

## Phase 5 — purge

Only after Phases 2–4 have held for a few days of real use:

- `rm -rf ~/.codex ~/.gemini ~/.claude ~/.claude.json` — reclaims **~13 GB**
  (9.1 + 3.1 + 0.67).
- Keep `~/.cursor` (Paseo provider), but delete the malformed `mcpServers` key.
- Keep `~/.config/bitwarden-agents/session` — `bw-mcp` depends on it.
- Do **not** delete `~/.buzz` in this pass; it is a separate tool with its own
  skill trees and was never in scope.

Take a tarball of each directory before deleting; the whole set compresses to
far less than the reclaimed space, and it makes the purge reversible for a
month.

## Phase 6 — make it reproducible

- `mcp.json`: currently machine-local and hand-edited. Decide between
  home-manager rendering (declarative, but omp writes to this file via
  `/mcp add`, so a store symlink would break those flows) and a fifth Syncthing
  folder. **Recommendation: leave hand-edited for now**, revisit once the
  content stops changing weekly.
- Skills: home-manager, per Phase 4.
- Server binaries: extend `home/agents-cli.nix` with any new bun globals.

## Open questions for Josh

1. `transcriptapi`, `pencil`, `git`, `github` — keep or drop? `pencil` needs
   its app declared as a cask; `github` needs Docker and a PAT.
2. The four per-project Claude servers (`excalidraw`, `adk-docs`,
   `grafana-demo`, `time`) — any worth keeping?
3. `~/.codex/skills/.system/` vendor skills — keep or drop?
4. Purge timing: immediately after parity, or after a soak period?


---

# REVISED after Josh's review — 2026-08-22

## Decisions

Dropped entirely: `transcriptapi`, `pencil`, `git` (harnesses have their own),
`github` (uses `gh`), `node_repl`, `computer-use`, and the four per-project
Claude servers (`excalidraw`, `adk-docs`, `grafana-demo`, `time`).
Vendor skills under `~/.codex/skills/.system/` are to be deleted.
Purge soaks before running.

Final keep-set — **10 servers**:

| Server | Transport | Command / URL |
|---|---|---|
| `browserless` | http | `mcp.browserless.io/mcp` |
| `cloudflare-api` | http | `mcp.cloudflare.com/mcp` |
| `context7` | http | `mcp.context7.com/mcp` |
| `agentmail` | http | `mcp.agentmail.to/mcp` |
| `gitnexus` | stdio | `gitnexus mcp` |
| `bitwarden` | stdio | `bw-mcp` |
| `1password` | stdio | `/Applications/1Password.app/Contents/MacOS/1password-mcp` |
| `adrafinil` | stdio | `/Applications/Adrafinil.app/Contents/Helpers/adrafinil mcp` |
| `exa` | stdio | `bunx exa-mcp-server@3.4.1` |
| `chrome-devtools` | stdio | `bunx chrome-devtools-mcp@1.7.0` |

## Correction to Phase 3

My earlier draft guessed at per-source skill toggles. The real mechanism is
`disabledProviders` (`omp://settings.md`), a **single shared array** that gates
both model providers and *discovery sources*: `native`, `claude`, `codex`,
`gemini`, `github`, `opencode`, `cursor`, `agents-md`. Disabling a discovery
source stops it contributing "context files, MCP servers, commands, skills,
hooks, tools, prompts, or settings" — exactly one switch for both MCP and
skills.

```yaml
disabledProviders: [claude, codex, gemini, cursor]
```

Two consequences that change the ordering:

1. **Skills and MCP are gated together.** Disabling `claude`/`codex` also stops
   their *skills* being discovered, so `~/.agents/skills` must be populated
   **before** this flag is set, or 27+ skills vanish at once.
2. **Arrays replace, they do not append.** `disabledProviders` is currently
   unset (empty). Any project-level `.omp/config.yml` that sets it would
   replace the global list wholesale.

Disabling `cursor` in omp does not affect `cursor-agent` — it only stops omp
importing Cursor's config. Cursor's own MCP set is then free to diverge, which
is intended.

## Status

- **Phase 1 + 2: DONE.** `~/.omp/agent/mcp.json` now declares all 10 servers on
  **both** machines, byte-identical. `npx` replaced with `bunx`, versions
  pinned (`exa-mcp-server@3.4.1`, `chrome-devtools-mcp@1.7.0`) so both machines
  run the same server builds. Every stdio binary verified present on both:
  `gitnexus`, `bw-mcp`, `bunx`, `1password-mcp`, `adrafinil`.
- **Phase 3: waiting on Josh** — one `disabledProviders` edit, after the skills
  move.
- **Phase 4 (skills): next.** Reconcile the diverged copies into
  `meigma/agent-skills`, delete `.system` vendor skills, render
  `~/.agents/skills` from the repo via home-manager.
- **Phase 5 (purge): soaking.**

## Carried risk

`exa` previously carried its API key **as a literal value** in
`~/.claude.json`. The migrated entry uses env-var indirection
(`"EXA_API_KEY": "EXA_API_KEY"`), so the key must now be present in the
environment or the server will not authenticate. The literal value is still
sitting in `~/.claude.json` until the purge, and it was printed to a terminal
during this session — **treat it as exposed and rotate it**, then store the new
value in 1Password and switch the entry to `!op read op://…`.
