import XCTest
@testable import ManagerCore

final class JsonMcpProviderTests: XCTestCase {
    func cursor(_ h: TempHome) -> JsonMcpProvider {
        JsonMcpProvider(JsonToolSpec(id: "cursor", name: "Cursor", files: [("global", ".cursor/mcp.json")],
                                     key: ["mcpServers"]), env: h.env)
    }

    func testMissingFileMeansNotInstalledAndNoItems() async throws {
        let h = TempHome(); defer { h.cleanup() }
        XCTAssertFalse(cursor(h).isInstalled())
        let items = try await cursor(h).load()
        XCTAssertTrue(items.isEmpty)
    }

    func testParkAndUnparkWithoutFlag() async throws {
        let h = TempHome(); defer { h.cleanup() }
        h.write(".cursor/mcp.json", """
        {
          "mcpServers": {
            "github": { "command": "npx", "args": ["-y", "gh"], "env": { "GITHUB_TOKEN": "ghp_x" } },
            "other": { "url": "https://a.b/mcp" }
          }
        }
        """)
        let p = cursor(h)
        var items = try await p.load()
        XCTAssertEqual(items.map(\.name), ["github", "other"])
        let gh = items[0]

        try await p.setEnabled(gh, false)
        XCTAssertFalse(h.read(".cursor/mcp.json").contains("github"))
        XCTAssertEqual(h.backups(of: ".cursor/mcp.json").count, 1)
        items = try await p.load()
        XCTAssertEqual(items.first { $0.name == "github" }?.enabled, false)
        XCTAssertEqual(items.first { $0.name == "github" }?.envKeys, ["GITHUB_TOKEN"])

        try await p.setEnabled(items.first { $0.name == "github" }!, true)
        XCTAssertTrue(h.read(".cursor/mcp.json").contains("ghp_x"))
        items = try await p.load()
        XCTAssertEqual(items.filter { $0.name == "github" }.map(\.enabled), [true])
        XCTAssertTrue(h.env.parking.all().isEmpty)
    }

    func testFlagToolsUseTheirOwnFlag() async throws {
        let h = TempHome(); defer { h.cleanup() }
        h.write("cline.json", #"{"mcpServers": {"a": {"command": "a", "disabled": true}}}"#)
        let p = JsonMcpProvider(JsonToolSpec(id: "cline", name: "Cline", files: [("global", "cline.json")],
                                             key: ["mcpServers"], flag: OffFlag("disabled", offValue: true)), env: h.env)
        var a = try await p.load()[0]
        XCTAssertFalse(a.enabled)
        try await p.setEnabled(a, true)
        XCTAssertFalse(h.read("cline.json").contains("disabled"))
        a = try await p.load()[0]
        XCTAssertTrue(a.enabled)
        try await p.setEnabled(a, false)
        XCTAssertTrue(h.read("cline.json").contains("\"disabled\": true"))
    }

    func testRemove() async throws {
        let h = TempHome(); defer { h.cleanup() }
        h.write(".cursor/mcp.json", #"{"mcpServers": {"a": {"command": "a"}, "b": {"command": "b"}}}"#)
        let p = cursor(h)
        let first = try await p.load()[0]
        try await p.remove(first)
        let names = try await p.load().map(\.name)
        XCTAssertEqual(names, ["b"])
    }
}

final class ClaudeCodeProviderTests: XCTestCase {
    func testLoadsGlobalProjectSharedAndPlugins() async throws {
        let h = TempHome(); defer { h.cleanup() }
        let proj = h.url.appendingPathComponent("proj").path
        h.write(".claude.json", """
        {
          "mcpServers": { "blender": { "command": "uv", "args": ["run", "blender-mcp"] } },
          "projects": {
            "\(proj)": {
              "mcpServers": { "local1": { "command": "x" } },
              "disabledMcpServers": ["local1"],
              "enabledMcpjsonServers": ["shared1"]
            }
          }
        }
        """)
        h.write("proj/.mcp.json", #"{"mcpServers": {"shared1": {"command": "s"}, "shared2": {"command": "t"}}}"#)
        h.runner.installed = ["claude"]
        h.runner.outputs["claude plugin list --json"] = """
        [{"id": "figma@official", "scope": "user", "enabled": true, "version": "1.0",
          "mcpServers": {"figma": {"type": "http", "url": "https://mcp.figma.com/mcp"}}}]
        """
        let p = ClaudeCodeProvider(env: h.env)
        let items = try await p.load()
        func find(_ n: String) -> Item? { items.first { $0.name == n } }

        XCTAssertEqual(find("blender")?.scope, "global")
        XCTAssertEqual(find("local1")?.enabled, false)
        XCTAssertEqual(find("shared1")?.enabled, true)
        XCTAssertEqual(find("shared2")?.health, .pending)
        XCTAssertEqual(find("shared2")?.canRemove, false)
        XCTAssertEqual(find("figma@official")?.kind, .plugin)
        XCTAssertEqual(find("figma")?.scope, "plugin: figma")
        XCTAssertEqual(find("figma")?.canToggle, false)

        // Turning a project server on edits only its list.
        try await p.setEnabled(find("local1")!, true)
        let j = try JsonText(file: h.url.appendingPathComponent(".claude.json").path)
        XCTAssertEqual(try j.value(at: ["projects", proj, "disabledMcpServers"]) as? [String], [])

        // Plugins go through the CLI.
        try await p.setEnabled(find("figma@official")!, false)
        XCTAssertTrue(h.runner.calls.contains("claude plugin disable figma@official -s user"))
    }

    func testHealthLines() {
        let ok = ClaudeCodeProvider.parseHealthLine("easyresume: /opt/homebrew/bin/node cli.js mcp - ✔ Connected")
        XCTAssertEqual(ok?.0, "easyresume")
        XCTAssertEqual(ok?.2, .connected)

        let plugin = ClaudeCodeProvider.parseHealthLine("plugin:figma:figma: https://mcp.figma.com/mcp (HTTP) - ! Needs authentication")
        XCTAssertEqual(plugin?.0, "plugin:figma:figma")
        XCTAssertEqual(plugin?.1, "https://mcp.figma.com/mcp")
        XCTAssertEqual(plugin?.2, .needsAuth)

        let bad = ClaudeCodeProvider.parseHealthLine("metapilot: http://127.0.0.1:1/mcp (HTTP) - ✘ Failed to connect — ECONNREFUSED")
        XCTAssertEqual(bad?.2, .failed("ECONNREFUSED"))

        XCTAssertNil(ClaudeCodeProvider.parseHealthLine("Checking MCP server health…"))
    }

    func testHealthAddsClaudeAiConnectors() async throws {
        let h = TempHome(); defer { h.cleanup() }
        h.write(".claude.json", #"{"mcpServers": {"blender": {"command": "uv"}}}"#)
        h.runner.installed = ["claude"]
        h.runner.outputs["claude mcp list"] = """
        Checking MCP server health…

        claude.ai Gmail: https://gmailmcp.googleapis.com/mcp/v1 - ✔ Connected
        blender: uv - ✘ Failed to connect — boom
        """
        let p = ClaudeCodeProvider(env: h.env)
        let items = try await p.load()
        let report = await p.health(for: items)
        XCTAssertEqual(report.extraItems.map(\.name), ["Gmail"])
        XCTAssertEqual(report.byItemID[items.first { $0.name == "blender" }!.id], .failed("boom"))
    }
}

final class CodexProviderTests: XCTestCase {
    let config = """
    [plugins."docs@openai"]
    enabled = true

    [mcp_servers.node_repl]
    command = "node"
    args = ["repl.js"]

    [mcp_servers.node_repl.env]
    TOKEN = "secret"
    """

    func testReadsTomlWithoutCli() async throws {
        let h = TempHome(); defer { h.cleanup() }
        h.write(".codex/config.toml", config)
        let p = CodexProvider(env: h.env)
        let items = try await p.load()
        XCTAssertEqual(items.map(\.name), ["node_repl", "docs@openai"])
        XCTAssertEqual(items[0].envKeys, ["TOKEN"])
        XCTAssertEqual(items[0].target, "node repl.js")

        try await p.setEnabled(items[0], false)
        XCTAssertTrue(h.read(".codex/config.toml").contains("[mcp_servers.node_repl]\nenabled = false"))
        try await p.setEnabled(items[1], false)
        XCTAssertEqual(TomlLite(h.read(".codex/config.toml")).values(["plugins", "docs@openai"])["enabled"] as? Bool, false)
    }

    func testCliListMarksPluginServers() async throws {
        let h = TempHome(); defer { h.cleanup() }
        h.write(".codex/config.toml", config)
        h.runner.installed = ["codex"]
        h.runner.outputs["codex mcp list --json"] = """
        [{"name": "node_repl", "enabled": true, "transport": {"type": "stdio", "command": "node", "args": ["repl.js"], "env": null, "env_vars": ["PATH"]}},
         {"name": "code-review", "enabled": false, "transport": {"type": "stdio", "command": "/bin/sh", "args": [], "cwd": "/Users/x/.codex/plugins/cache/openai-bundled/code-review/1.0/."}}]
        """
        h.write(".codex/config.toml", config + "\n\n[plugins.\"supabase@openai-curated\"]\nenabled = true\n")
        h.write(".codex/plugins/cache/openai-curated/supabase/1.0/.mcp.json",
                #"{"mcpServers": {"supabase": {"url": "https://mcp.supabase.com/mcp"}}}"#)
        h.runner.outputs["codex mcp list --json"]! = String(h.runner.outputs["codex mcp list --json"]!.dropLast(1))
            + #", {"name": "supabase", "enabled": true, "transport": {"type": "streamable_http", "url": "https://mcp.supabase.com/mcp"}}]"#
        let items = try await CodexProvider(env: h.env).load()
        let supa = items.first { $0.name == "supabase" && $0.kind == .mcp }
        XCTAssertEqual(supa?.scope, "plugin: supabase")
        XCTAssertEqual(supa?.canToggle, false)
        XCTAssertEqual(supa?.canRemove, false)
        let review = items.first { $0.name == "code-review" }
        XCTAssertEqual(review?.scope, "plugin: code-review")
        XCTAssertEqual(review?.canToggle, false)
        XCTAssertEqual(items.first { $0.name == "node_repl" }?.canRemove, true)
    }
}

final class ContinueProviderTests: XCTestCase {
    func testBlocksParkAndRestore() async throws {
        let h = TempHome(); defer { h.cleanup() }
        h.write(".continue/config.yaml", """
        name: My config
        models:
          - name: gpt
        mcpServers:
          - name: sqlite
            command: npx
            args:
              - mcp-sqlite
          - name: web
            type: streamable-http
            url: https://a.b/mcp
        rules:
          - be nice
        """)
        let p = ContinueProvider(env: h.env)
        var items = try await p.load()
        XCTAssertEqual(items.map(\.name), ["sqlite", "web"])
        XCTAssertEqual(items[0].target, "npx mcp-sqlite")

        try await p.setEnabled(items[0], false)
        XCTAssertFalse(h.read(".continue/config.yaml").contains("sqlite"))
        XCTAssertTrue(h.read(".continue/config.yaml").contains("rules:"))
        items = try await p.load()
        XCTAssertEqual(items.first { $0.name == "sqlite" }?.enabled, false)

        try await p.setEnabled(items.first { $0.name == "sqlite" }!, true)
        items = try await p.load()
        XCTAssertEqual(Set(items.filter(\.enabled).map(\.name)), ["sqlite", "web"])
        XCTAssertTrue(h.read(".continue/config.yaml").contains("rules:\n  - be nice"))
    }
}

final class SafeFileWriterTests: XCTestCase {
    func testKeepsThreeBackupsAndNeverTouchesOthers() throws {
        let h = TempHome(); defer { h.cleanup() }
        let path = h.url.appendingPathComponent("c.json").path
        h.write("c.json.bak-mine", "keep me")              // the user's own backups
        h.write("c.json.aitm-bak-handmade", "keep me too")
        for k in 0..<6 {
            try SafeFileWriter.write("{\"v\": \(k)}", to: path)
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertEqual(h.read("c.json"), "{\"v\": 5}")
        XCTAssertEqual(h.backups(of: "c.json").filter { $0.count == "c.json.aitm-bak-".count + 19 }.count, 3)
        XCTAssertEqual(h.read("c.json.bak-mine"), "keep me")
        XCTAssertEqual(h.read("c.json.aitm-bak-handmade"), "keep me too")
    }
}
