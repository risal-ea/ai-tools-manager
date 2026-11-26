import XCTest
@testable import ManagerCore

final class JsonTextTests: XCTestCase {
    let sample = """
    {
      "numberOfStartups": 42,
      "cost": 0.1,
      "mcpServers": {
        "github": {
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-github"]
        },
        "figma": { "type": "http", "url": "https://example.com/mcp" }
      },
      "zzz": true
    }
    """

    func testReadsValuesAndKeysInOrder() throws {
        let j = JsonText(sample)
        XCTAssertEqual(try j.keys(at: ["mcpServers"]), ["github", "figma"])
        let gh = try j.value(at: ["mcpServers", "github"]) as? [String: Any]
        XCTAssertEqual(gh?["command"] as? String, "npx")
        XCTAssertNil(try j.value(at: ["nope"]))
    }

    func testRemoveKeepsEverythingElse() throws {
        var j = JsonText(sample)
        XCTAssertTrue(try j.remove(at: ["mcpServers", "figma"]))
        XCTAssertFalse(j.text.contains("figma"))
        XCTAssertTrue(j.text.contains("\"cost\": 0.1,"))           // numbers untouched
        XCTAssertTrue(j.text.contains("\"numberOfStartups\": 42"))
        XCTAssertEqual(try j.keys(at: ["mcpServers"]), ["github"])

        XCTAssertTrue(try j.remove(at: ["mcpServers", "github"]))
        XCTAssertEqual(try j.keys(at: ["mcpServers"]), [])
        XCTAssertFalse(try j.remove(at: ["mcpServers", "github"]))
    }

    func testRemoveFirstOfMany() throws {
        var j = JsonText(sample)
        try j.remove(at: ["numberOfStartups"])
        XCTAssertEqual(try j.keys(at: []), ["cost", "mcpServers", "zzz"])
    }

    func testRawParkAndRestoreRoundTrip() throws {
        var j = JsonText(sample)
        let raw = try XCTUnwrap(try j.raw(at: ["mcpServers", "github"]))
        try j.remove(at: ["mcpServers", "github"])
        try j.set(raw, at: ["mcpServers", "github"])
        let gh = try j.value(at: ["mcpServers", "github"]) as? [String: Any]
        XCTAssertEqual(gh?["args"] as? [String], ["-y", "@modelcontextprotocol/server-github"])
    }

    func testSetReplacesAndCreatesParents() throws {
        var j = JsonText(sample)
        try j.set("false", at: ["zzz"])
        XCTAssertEqual(try j.value(at: ["zzz"]) as? Bool, false)

        try j.set("[\"a\"]", at: ["projects", "/Users/me/app", "disabledMcpServers"])
        XCTAssertEqual(try j.value(at: ["projects", "/Users/me/app", "disabledMcpServers"]) as? [String], ["a"])
        XCTAssertTrue(j.text.contains("\"cost\": 0.1"))
    }

    func testSetIntoEmptyObject() throws {
        var j = JsonText("{\n  \"mcpServers\": {}\n}\n")
        try j.set("{\"command\": \"x\"}", at: ["mcpServers", "a"])
        XCTAssertEqual(try j.keys(at: ["mcpServers"]), ["a"])
    }

    func testJsoncCommentsAndTrailingCommasSurvive() throws {
        var j = JsonText("""
        // Zed settings
        {
          "theme": "One Dark", // my theme
          "context_servers": {
            /* first */
            "a": { "command": "a" },
            "b": { "command": "b" },
          },
        }
        """)
        XCTAssertEqual(try j.keys(at: ["context_servers"]), ["a", "b"])
        try j.remove(at: ["context_servers", "b"])
        XCTAssertTrue(j.text.contains("// Zed settings"))
        XCTAssertTrue(j.text.contains("// my theme"))
        XCTAssertEqual(try j.keys(at: ["context_servers"]), ["a"])
        try j.validate()
    }

    func testInvalidJsonIsRejected() {
        XCTAssertThrowsError(try JsonText("{ \"a\": }").validate())
        var j = JsonText("{}")
        XCTAssertThrowsError(try j.set("{not json", at: ["a"]))
    }

    func testUnicodeEscapes() throws {
        let j = JsonText(#"{"k": "café 😀"}"#)
        XCTAssertEqual(try j.value(at: ["k"]) as? String, "café 😀")
    }
}
