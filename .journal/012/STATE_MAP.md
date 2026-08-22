# Workstation state map — 2026-08-22

What actually breaks when Josh closes the laptop and walks to the Studio.
Sizes measured on each machine; "absent" means the path does not exist.

## Agent and workspace state

| Path | MacBook | Studio | What it holds |
|---|---|---|---|
| `~/.omp` | 5.5 GB | **absent** | `agent/sessions` 4.1 GB, `agent.db`, `history.db`, `models.db`, `config.yml` |
| `~/.paseo` | 1.0 GB | **absent** | `agents/` (17 workspaces, 392 KB of JSON), `config.json`, daemon keypair, 30 MB of daemon logs |
| `~/Library/Application Support/Paseo` | 33 MB | — | desktop app state |
| `~/.claude` | 669 MB | 17 MB | 27 skills + config |
| `~/.claude.json` | 356 KB | — | per-project `mcpServers` blocks (173 matches) |
| `~/.codex` | 9.1 GB | 744 MB | 29 skills, `config.toml` (12 MCP servers), `memories/`, `vendor_imports/` |
| `~/.cursor` | 1.0 GB | 639 MB | `mcp.json` (2 servers) |
| `~/.gemini` | 3.1 GB | 6.5 MB | `settings.json` (1 server) |
| `~/.buzz` | present | absent | another agent tool, with its own `.agents/.claude/.codex/.goose` skill trees |

The Studio has **no** omp and **no** Paseo state at all. Every open session,
workspace registration, and agent history lives only on the MacBook.

## Skills — six locations, one real source

`~/code/agent-skills` is a git checkout of `meigma/agent-skills`. The rest are
copies of it:

- `~/.claude/skills` — 27
- `~/.codex/skills` — 29 (same set plus `references/`, `scripts/`)
- `~/.config/ramp/skills` — 2
- `~/.codex/vendor_imports/skills`, `~/.codex/memories/skills` — 3 each
- `~/.buzz/{.agents,.claude,.codex,.goose}/skills`
- plus repo-local `.agents/skills` in `GilmanLab/root`

## MCP servers — four incompatible config formats

| File | Format | Servers |
|---|---|---|
| `~/.codex/config.toml` | TOML `[mcp_servers.*]` | 12 |
| `~/.claude.json` | JSON, per-project `mcpServers` | many |
| `~/.cursor/mcp.json` | JSON | 2 |
| `~/.gemini/settings.json` | JSON | 1 |

`~/.omp/agent/config.yml` defines no MCP servers; omp inherits them elsewhere.

## Classification

**Derivable — should be generated, never synced.** Skills and MCP definitions.
One source of truth, rendered into each tool's expected path and format by
home-manager. Kills the scatter and makes both machines identical by
construction.

**Live session state — must not be file-synced.** `~/.omp/agent/*.db` and
Paseo's daemon state are SQLite with `-wal`/`-shm` sidecars. File-level sync of
an open SQLite database corrupts it, exactly like `.git`.

**Machine identity — must stay local.** `~/.paseo/daemon-keypair.json`,
`~/.omp/install-id`, per-tool client IDs.

**Caches — should never leave the machine.** Most of the 9.1 GB in `~/.codex`
and 3.1 GB in `~/.gemini`.
