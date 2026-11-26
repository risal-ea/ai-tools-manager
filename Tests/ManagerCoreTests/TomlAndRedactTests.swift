import XCTest
@testable import ManagerCore

final class TomlLiteTests: XCTestCase {
    let sample = """
    model = "gpt-5"

    [plugins."documents@openai-primary-runtime"]
    enabled = true

    [mcp_servers.node_repl]
    command = "node"
    args = ["repl.js", "--port", "1"]

    [mcp_servers.node_repl.env]
    API_KEY = "secret-value"

    [mcp_servers.staging]
    url = "https://example.com/mcp"
    enabled = true
    """

    func testTablesAndValues() {
        let t = TomlLite(sample)
        XCTAssertEqual(t.tables().map(\.path), [
            ["plugins", "documents@openai-primary-runtime"],
            ["mcp_servers", "node_repl"],
            ["mcp_servers", "node_repl", "env"],
            ["mcp_servers", "staging"],
        ])
        let v = t.values(["mcp_servers", "node_repl"])
        XCTAssertEqual(v["command"] as? String, "node")
        XCTAssertEqual(v["args"] as? [String], ["repl.js", "--port", "1"])
        XCTAssertEqual(t.keys(["mcp_servers", "node_repl", "env"]), ["API_KEY"])
    }

    func testSetBoolReplacesOrInserts() {
        var t = TomlLite(sample)
        t.setBool("enabled", false, in: ["mcp_servers", "staging"])
        t.setBool("enabled", false, in: ["mcp_servers", "node_repl"])
        XCTAssertEqual(t.values(["mcp_servers", "staging"])["enabled"] as? Bool, false)
        XCTAssertEqual(t.values(["mcp_servers", "node_repl"])["enabled"] as? Bool, false)
        XCTAssertTrue(t.text.hasPrefix("model = \"gpt-5\""))
        XCTAssertEqual(t.text.components(separatedBy: "enabled = false").count, 3)
    }

    func testRemoveTableTakesSubtables() {
        var t = TomlLite(sample)
        let cut = t.removeTable(["mcp_servers", "node_repl"])
        XCTAssertTrue(cut?.contains("API_KEY") ?? false)
        XCTAssertEqual(t.tables().map(\.path), [["plugins", "documents@openai-primary-runtime"], ["mcp_servers", "staging"]])
    }
}

final class RedactTests: XCTestCase {
    func testMasksSecretArgsAndUrls() {
        XCTAssertEqual(Redact.args(["--api-key", "abc", "--port", "1"]), ["--api-key", "••••", "--port", "1"])
        XCTAssertEqual(Redact.args(["--token=abc"]), ["--token=••••"])
        XCTAssertEqual(Redact.args(["GITHUB_TOKEN=abc"]), ["GITHUB_TOKEN=••••"])
        XCTAssertFalse(Redact.url("https://x.com/mcp?api_key=abc&v=1").contains("abc"))
        XCTAssertTrue(Redact.url("https://x.com/mcp?api_key=abc&v=1").contains("v=1"))
        XCTAssertFalse(Redact.url("https://user:pw@x.com/mcp").contains("pw@"))
    }

    func testServerConfigShowsKeyNamesOnly() {
        var it = Item(toolID: "t", name: "n", kind: .mcp, scope: "global")
        ServerConfig.fill(&it, from: ["command": "npx", "args": ["-y", "pkg"], "env": ["GITHUB_TOKEN": "ghp_secret"]])
        XCTAssertEqual(it.envKeys, ["GITHUB_TOKEN"])
        XCTAssertEqual(it.target, "npx -y pkg")
        XCTAssertFalse("\(it)".contains("ghp_secret"))

        var oc = Item(toolID: "t", name: "n", kind: .mcp, scope: "global")
        ServerConfig.fill(&oc, from: ["type": "local", "command": ["bun", "x", "srv"], "environment": ["K": "v"]])
        XCTAssertEqual(oc.target, "bun x srv")
        XCTAssertEqual(oc.envKeys, ["K"])

        var remote = Item(toolID: "t", name: "n", kind: .mcp, scope: "global")
        ServerConfig.fill(&remote, from: ["serverUrl": "https://a.b/mcp"])
        XCTAssertEqual(remote.transport, "http")
    }
}
