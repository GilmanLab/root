# MCP + skills consolidation into oh-my-pi — 2026-08-22

## Where MCP servers are defined today

| Source | File | Servers |
|---|---|---|
| **omp native (user)** | `~/.omp/agent/mcp.json` | `browserless`, `cloudflare-api`, `gitnexus` (+ `disabledServers: [node_repl]`) |
| Claude Code | `~/.claude.json` top level | `adrafinil`, `chrome-devtools`, `context7`, `exa`, `pencil`, `transcriptapi`, `agentmail`, `bitwarden`, `1password` |
| Claude Code | `~/.claude.json` per project | `excalidraw`, `exa`, `adk-docs`, `grafana-demo`, `context7`, `git`, `github`, `time`, `agentmail` |
| Codex | `~/.codex/config.toml` | `context7`, `exa`, `chrome-devtools`, `node_repl`, `computer-use`, `agentmail`, `bitwarden`, `totem`, `1password` |
| Cursor | `~/.cursor/mcp.json` | `context7`, `github`, `git`, `exa`, `chrome-devtools`, **`mcpServers`** ← malformed nested key |
| Gemini CLI | `~/.gemini/settings.json` | `chrome-devtools`, `pencil` |

Only 3 of the ~20 distinct servers are actually omp-native. Everything else
reaches omp through its **import** of other tools' configs, in this precedence:
omp native → omp extensions → Claude Code → Claude plugins + Codex → Gemini CLI
→ OpenCode → Cursor/Windsurf → VS Code → root `mcp.json`.

So the current setup is not "omp plus leftovers" — omp is *depending on* the
Claude/Codex/Cursor/Gemini files. Deleting them without migrating first silently
removes working tools.

## Where skills live today

| Location | Count | Notes |
|---|---|---|
| `~/code/agent-skills` | — | git checkout of `meigma/agent-skills`, the real source |
| `~/.claude/skills` | 27 | omp `claude` provider, priority 80 |
| `~/.codex/skills` | 29 | omp `codex` provider, priority 70. Contains extras: `.system/` (6 vendor skills), `references/`, `scripts/`, and a diverged `cli/SKILL.md` |
| `~/.config/ramp/skills` | 2 | not read by omp |
| `~/.codex/vendor_imports/skills`, `~/.codex/memories/skills` | 3 each | not read by omp |
| `~/.buzz/{.agents,.claude,.codex,.goose}/skills` | — | not read by omp |
| repo `.agents/skills` | 8 | omp `agents` provider (project level) |

`~/.agents/` (the user-level canonical omp location) **does not exist**.
`~/.claude/skills` and `~/.codex/skills` are near-copies that have already
diverged: `cli/SKILL.md` differs between them.

## Target

- Skills → one git-tracked source, rendered by home-manager into
  `~/.agents/skills/<name>/SKILL.md` (omp `agents` provider, user level; its
  `enableAgentsUser` toggle is independent of the Claude/Codex toggles).
- MCP → all servers declared in `~/.omp/agent/mcp.json`, secrets kept out via
  `${VAR}` expansion or `!command` indirection.
- Third-party imports switched off with `enableClaudeUser: false`,
  `enableCodexUser: false` etc. **before** any files are deleted — reversible,
  and it proves nothing was lost.

## Why not Syncthing for this

`~/.omp/agent/` holds `agent.db`, `history.db`, `models.db`, each with `-wal`
and `-shm` sidecars, plus 4.1 GB of `sessions/`. File-level sync of live SQLite
corrupts it, the same failure class as `.git`. And the parts worth sharing —
`mcp.json`, `config.yml`, skills — are declarative text that home-manager
already renders identically on both machines from git. Syncthing would add
conflict files and a second source of truth to solve a problem git already
solves better.

Auth is a further reason: MCP OAuth credentials live in `agent.db` / the auth
broker keyed by `mcp_oauth:profile:<profile>:<url>`, not in `mcp.json`. So the
config is safe to commit, and the credentials are machine-local by design —
exactly the split we want.
