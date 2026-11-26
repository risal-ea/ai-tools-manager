# AI Tools Manager

See and control the **MCP servers and plugins of every AI tool on your Mac** in one place:
Claude Code, Claude Desktop, Codex, Cursor, VS Code, Windsurf, Gemini CLI, Zed and more.
Turn them on or off, or remove them. It also lives in your menu bar.

[![Download for macOS](https://img.shields.io/badge/Download-macOS-black?style=for-the-badge&logo=apple)](https://github.com/risal-ea/ai-tools-manager/releases/latest/download/AI-Tools-Manager.zip)

macOS 14 or later · Apple silicon and Intel · free

## Install

1. [Download](https://github.com/risal-ea/ai-tools-manager/releases/latest/download/AI-Tools-Manager.zip) and unzip.
2. Move **AI Tools Manager.app** to your Applications folder.
3. Open it. The app isn't notarized by Apple, so the first time macOS blocks it:
   go to **System Settings → Privacy & Security** and click **Open Anyway**.

## What it does

- **One list** of every MCP server and plugin, from every AI tool it finds. Tools you don't have are hidden.
- **Status** for each server: connected, needs sign-in, or failed.
- **On/off switch** and **Remove** for each one.
- **Menu bar icon** for quick switches. It shows ⚠︎ and a count when a server fails.
  Turn on "Open at login" in its panel to keep it there.

Restart the AI tool after a change: running apps keep their servers until they restart.

## Is it safe?

- If the tool has its own command (`claude`, `codex`), the app uses it.
- Otherwise it changes only that one entry in the config file. Comments and formatting stay as they were.
- Before every change it saves a backup next to the file (`<file>.aitm-bak-<time>`, newest 3 kept).
- Secret values (API keys, tokens) are never shown.
- The app itself sends nothing anywhere. (The status check runs each tool's own `mcp list` command.)

## Supported tools

Claude Code · Claude Desktop · Codex · Cursor · VS Code · Windsurf · Gemini CLI · Zed · Cline · Roo Code ·
OpenCode · Continue · LM Studio · Amazon Q · Kiro · GitHub Copilot CLI.
claude.ai and ChatGPT connectors live online, so the app links to their settings.

## Build from source

```bash
swift run AIToolsManager          # run the app
swift run aitm                    # the same list in the terminal
swift test                        # tests (use temp folders, never your real files)
./scripts/build-app.sh            # build the .app into ~/Applications
```

Needs Xcode (Swift 5.10+). To add a tool, add one entry to `Sources/ManagerCore/Providers/Registry.swift`.
