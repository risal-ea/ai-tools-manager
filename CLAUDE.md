# AI Tools Manager

A SwiftUI Mac app (+ `aitm` CLI) that lists and toggles/removes the MCP servers and plugins of every AI tool
on this Mac. See README.md for the tool table and code map.

## Commands
- `swift build` / `swift test` (25 tests; temp folders + a fake CLI, never real config files)
- `swift run AIToolsManager` (window), `swift run aitm [--health]` (terminal list)
- `./scripts/build-app.sh [--no-install|--zip]`: universal release `.app` into `build/`, then `~/Applications`
  (`--zip` makes `build/AI-Tools-Manager.zip`; release: `gh release create vX.Y.Z build/AI-Tools-Manager.zip`,
  the README download button points at `releases/latest/download/AI-Tools-Manager.zip`)

## Safety rules (do not weaken)
- **CLI first**: if a tool has a CLI (`claude`, `codex`), changes go through it.
- **One-entry edits**: otherwise change only the one entry; keep comments/order/spacing/numbers
  (`JsonText` for JSON/JSONC, `TomlLite` for TOML). Never re-serialize a whole file.
- **All writes go through `SafeFileWriter`**: backup `<file>.aitm-bak-<yyyyMMdd-HHmmss-SSS>` (keeps newest 3),
  temp file, atomic rename. Backup cleanup must only touch files matching that exact pattern: the user has
  their own `.bak-*` files (e.g. `config.toml.bak-something`) that must never be deleted.
- **Off without an on/off flag = parked**: the entry moves to
  `~/Library/Application Support/AIToolsManager/parked.json` (mode 600) and is restored on "on".
- **Never show or log secrets**: env/header names only; secret-looking values masked (`Redact`).
- Read-only: servers from plugins (Claude Code and Codex), a project's `.mcp.json`, cloud connectors.

## Testing against real configs
Only with throwaway servers (`claude mcp add test-dummy -- echo hi`, `codex mcp add test-dummy -- echo hi`),
copy the real config to the scratchpad first, and remove the dummy afterwards. Note `codex mcp add` itself
rewrites the whole `config.toml` (reorders keys, `120` → `120.0`).

## Known gaps
- Cursor, VS Code, Cline, Roo, Windsurf, Gemini, Zed, OpenCode, LM Studio, Amazon Q, Continue are not
  installed on this Mac: tested on sample files only. Paths/keys live in `Providers/Registry.swift`.
  Checked against docs 2026-11-26: Windsurf, VS Code (`servers`), Zed (`context_servers`), OpenCode, Cursor OK.
  Open questions: Amazon Q's `~/.aws/amazonq/mcp.json` is the *legacy* file (new: agent files in
  `~/.aws/amazonq/cli-agents/`, not read yet); Roo Code's file may be `mcp_settings.json` or
  `cline_mcp_settings.json` by version; LM Studio may use `~/.cache/lm-studio/mcp.json` on some macOS builds;
  `~/.continue/mcpServers/` (home) is undocumented (only the workspace folder is). Kiro and Copilot CLI
  entries were added from docs/search, also untested.
- A running Claude Code session can rewrite `~/.claude.json` and undo an on/off change.
- No screenshots possible from the terminal (no Screen Recording permission).

## User preferences
- Explain Swift ideas (protocols, SwiftUI, `@Observable`, `Process`, Codable) as they come up.
- Nothing is committed unless asked.
