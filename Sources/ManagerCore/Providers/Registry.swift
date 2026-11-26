import Foundation

/// Every AI tool the app knows. A new tool = one new entry here.
/// Paths are relative to your home folder.
public enum Registry {
    static let vsGlobal = "Library/Application Support/Code/User/globalStorage"
    static let cursorGlobal = "Library/Application Support/Cursor/User/globalStorage"

    public static func providers(env: ToolEnv) -> [ToolProvider] {
        let json: [JsonToolSpec] = [
            JsonToolSpec(id: "claude-desktop", name: "Claude Desktop",
                         files: [("global", "Library/Application Support/Claude/claude_desktop_config.json")],
                         key: ["mcpServers"], apps: ["/Applications/Claude.app"],
                         extensionsDir: "Library/Application Support/Claude/Claude Extensions",
                         extensionsNote: "A Claude Desktop extension: turn it on/off or remove it in Claude Desktop → Settings → Extensions."),
            JsonToolSpec(id: "cursor", name: "Cursor",
                         files: [("global", ".cursor/mcp.json")],
                         key: ["mcpServers"], apps: ["/Applications/Cursor.app"], cli: "cursor"),
            JsonToolSpec(id: "vscode", name: "VS Code",
                         files: [("VS Code", "Library/Application Support/Code/User/mcp.json"),
                                 ("VS Code Insiders", "Library/Application Support/Code - Insiders/User/mcp.json")],
                         key: ["servers"],
                         apps: ["/Applications/Visual Studio Code.app", "/Applications/Visual Studio Code - Insiders.app"],
                         cli: "code"),
            JsonToolSpec(id: "cline", name: "Cline",
                         files: [("in VS Code", "\(vsGlobal)/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"),
                                 ("in Cursor", "\(cursorGlobal)/saoudrizwan.claude-dev/settings/cline_mcp_settings.json")],
                         key: ["mcpServers"], flag: OffFlag("disabled", offValue: true), needsRestart: false),
            JsonToolSpec(id: "roo", name: "Roo Code",
                         files: [("in VS Code", "\(vsGlobal)/rooveterinaryinc.roo-cline/settings/mcp_settings.json"),
                                 ("in Cursor", "\(cursorGlobal)/rooveterinaryinc.roo-cline/settings/mcp_settings.json")],
                         key: ["mcpServers"], flag: OffFlag("disabled", offValue: true), needsRestart: false),
            JsonToolSpec(id: "windsurf", name: "Windsurf",
                         files: [("global", ".codeium/windsurf/mcp_config.json")],
                         key: ["mcpServers"], apps: ["/Applications/Windsurf.app"], cli: "windsurf"),
            JsonToolSpec(id: "gemini", name: "Gemini CLI",
                         files: [("global", ".gemini/settings.json")],
                         key: ["mcpServers"], cli: "gemini",
                         extensionsDir: ".gemini/extensions",
                         extensionsNote: "A Gemini CLI extension: use `gemini extensions disable/uninstall <name>`."),
            JsonToolSpec(id: "zed", name: "Zed",
                         files: [("global", ".config/zed/settings.json")],
                         key: ["context_servers"], apps: ["/Applications/Zed.app"], cli: "zed", needsRestart: false),
            JsonToolSpec(id: "opencode", name: "OpenCode",
                         files: [("opencode.json", ".config/opencode/opencode.json"),
                                 ("opencode.jsonc", ".config/opencode/opencode.jsonc")],
                         key: ["mcp"], flag: OffFlag("enabled", offValue: false), cli: "opencode"),
            JsonToolSpec(id: "lmstudio", name: "LM Studio",
                         files: [("global", ".lmstudio/mcp.json")],
                         key: ["mcpServers"], apps: ["/Applications/LM Studio.app"]),
            JsonToolSpec(id: "amazonq", name: "Amazon Q",
                         files: [("global", ".aws/amazonq/mcp.json")],
                         key: ["mcpServers"], cli: "q"),
            // Amazon's successor to the Q CLI; entries have a "disabled" flag.
            JsonToolSpec(id: "kiro", name: "Kiro",
                         files: [("global", ".kiro/settings/mcp.json")],
                         key: ["mcpServers"], flag: OffFlag("disabled", offValue: true),
                         apps: ["/Applications/Kiro.app"], cli: "kiro-cli"),
            JsonToolSpec(id: "copilot-cli", name: "GitHub Copilot CLI",
                         files: [("global", ".copilot/mcp-config.json")],
                         key: ["mcpServers"], cli: "copilot"),
        ]
        return [ClaudeCodeProvider(env: env)]
            + [JsonMcpProvider(json[0], env: env)]
            + [CodexProvider(env: env)]
            + json.dropFirst().map { JsonMcpProvider($0, env: env) as ToolProvider }
            + [ContinueProvider(env: env)]
    }

    /// Connectors that live in the cloud, not on this Mac.
    public static let cloudLinks: [(name: String, url: String)] = [
        ("claude.ai connectors", "https://claude.ai/settings/connectors"),
        ("ChatGPT connectors", "https://chatgpt.com/#settings/Connectors"),
    ]
}
