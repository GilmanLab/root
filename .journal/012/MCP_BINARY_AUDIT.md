# MCP local-binary dependencies — 2026-08-22

Josh flagged GitNexus as possibly unmanaged. It is, and it is not alone: every
stdio MCP server depends on a local binary, and those binaries are installed
ad hoc through three different package managers plus one hand-placed script.

## Inventory

| Server | Source config | Command | MacBook | Studio |
|---|---|---|---|---|
| `gitnexus` | `~/.omp/agent/mcp.json` | `/Users/josh/.nodenv/shims/gitnexus mcp` | ok | **missing** |
| `bitwarden` | `~/.codex/config.toml` | `/Users/josh/.local/bin/bw-mcp` | ok | **missing** |
| `totem` | `~/.codex/config.toml` | `~/.nodenv/versions/24.12.0/bin/node ~/tools/totem-whoop/dist/server.js` | ok | **missing** |
| `1password` | `~/.codex/config.toml` | `1password-mcp` (`/usr/local/bin`) | ok | **missing** |
| `node_repl` | `~/.codex/config.toml` | inside `ChatGPT.app` | ok | ok |
| `computer-use` | `~/.codex/config.toml` | relative path into `Codex Computer Use.app` | ok | n/a |
| `exa`, `chrome-devtools` | `~/.codex/config.toml` | `npx -y …` | ok | ok (Homebrew `npx`) |
| `browserless`, `cloudflare-api`, `context7`, `agentmail` | mixed | HTTP endpoints | ok | ok |

Remote (`type: http`) servers are portable by construction. Every failure is a
stdio server pointing at a path that exists on one machine only.

## Root causes

1. **Absolute machine-specific paths in synced config.** `gitnexus` is pinned to
   `/Users/josh/.nodenv/shims/gitnexus`. Even after installing gitnexus on the
   Studio, the entry only works if that exact nodenv shim path exists. A bare
   `gitnexus` resolved through `PATH` would be portable.
2. **Divergent Node toolchains.** MacBook: nodenv managing six versions with
   24.12.0 global, `node` = `~/.nodenv/shims/node` v24.12.0, and npm globals
   (`gitnexus`, `@browserless.io/cli`, `corepack`, and a linked
   `@thebriangao/totem`) installed *into that version*. Studio: nodenv present
   but **no versions installed** — `nodenv versions` lists only `system`, and
   `node` is Homebrew's v26.7.0. So npm globals on the MacBook live in a
   directory that has no counterpart on the Studio.
3. **Hand-placed binaries.** `/Users/josh/.local/bin/bw-mcp` and
   `/usr/local/bin/1password-mcp` are not owned by any package manager.
4. **A local dev checkout as a server.** `totem` runs
   `~/tools/totem-whoop/dist/server.js`, a built artifact from a local repo.

## Notes

- Nothing here is broken on the MacBook; this is purely a second-machine gap.
- It becomes urgent the moment MCP config is consolidated into
  `~/.omp/agent/mcp.json` and synced: a shared config that names machine-local
  paths fails on whichever machine lacks them, and it fails at MCP connect time
  rather than loudly at startup.
- Same class as the `omp` gap: tools installed outside Nix and outside the
  application inventory are invisible until a second machine needs them.
