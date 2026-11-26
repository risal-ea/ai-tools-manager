import Foundation

/// Codex: ~/.codex/config.toml (`[mcp_servers.<name>]`, `[plugins."<id>"]`, both with `enabled`).
/// `codex mcp list --json` also shows the servers that come with Codex plugins.
public struct CodexProvider: ToolProvider {
    let env: ToolEnv
    public init(env: ToolEnv) { self.env = env }

    public let id = "codex"
    public let name = "Codex"
    public var needsRestart: Bool { true }

    var configFile: String { env.path(".codex/config.toml") }
    var hasCLI: Bool { env.runner.find("codex") != nil }

    public func isInstalled() -> Bool { env.exists(configFile) || hasCLI }

    func toml() throws -> TomlLite {
        guard env.exists(configFile) else { return TomlLite("") }
        return TomlLite(try String(contentsOfFile: configFile, encoding: .utf8))
    }

    public func load() async throws -> [Item] {
        let t = try toml()
        let tables = t.tables()
        let configured = Set(tables.filter { $0.path.count == 2 && $0.path[0] == "mcp_servers" }.map { $0.path[1] })
        var items: [Item] = []
        var seen = Set<String>()
        let installedPlugins = Set(tables.filter { $0.path.count == 2 && $0.path[0] == "plugins" }.map { $0.path[1] })
        let pluginOf = pluginServers(installed: installedPlugins)

        // The CLI knows every server, including those from plugins.
        if hasCLI, let r = try? await env.runner.run("codex", ["mcp", "list", "--json"]), r.ok,
           let list = try? JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [[String: Any]] {
            for s in list {
                guard let name = s["name"] as? String else { continue }
                let tr = s["transport"] as? [String: Any] ?? [:]
                // Not in config.toml = it comes from somewhere else (a plugin): never edit it here.
                let fromPlugin = configured.contains(name) ? nil : (Self.pluginName(tr) ?? pluginOf[name])
                let scope = configured.contains(name) ? "global" : "plugin: \(fromPlugin ?? "?")"
                var it = Item(toolID: id, name: name, kind: .mcp, scope: scope)
                it.enabled = s["enabled"] as? Bool ?? true
                if let url = tr["url"] as? String {
                    it.transport = "http"
                    it.target = Redact.url(url)
                } else {
                    it.transport = "stdio"
                    it.target = Redact.commandLine(tr["command"] as? String, tr["args"] as? [String] ?? [])
                }
                let envNames = Array((tr["env"] as? [String: Any] ?? [:]).keys) + (tr["env_vars"] as? [String] ?? [])
                it.envKeys = Array(Set(envNames)).sorted()
                let headers = Array((tr["http_headers"] as? [String: Any] ?? [:]).keys)
                    + Array((tr["env_http_headers"] as? [String: Any] ?? [:]).keys)
                it.headerKeys = headers.sorted()
                if let reason = s["disabled_reason"] as? String { it.note = reason }
                it.configPath = configFile
                if configured.contains(name) {
                    it.canToggle = true
                    it.canRemove = true
                    it.ref = ["kind": "server"]
                } else {
                    it.note = fromPlugin != nil
                        ? "Comes with the Codex plugin \(fromPlugin!): turn the plugin off to stop it."
                        : "Not in ~/.codex/config.toml (it comes from a plugin or another config), so it can't be changed here."
                }
                items.append(it)
                seen.insert(name)
            }
        }

        // No CLI (or it failed): read config.toml directly.
        for name in configured.sorted() where !seen.contains(name) {
            let v = t.values(["mcp_servers", name])
            var it = Item(toolID: id, name: name, kind: .mcp, scope: "global")
            it.enabled = v["enabled"] as? Bool ?? true
            if let url = v["url"] as? String {
                it.transport = "http"
                it.target = Redact.url(url)
            } else {
                it.transport = "stdio"
                it.target = Redact.commandLine(v["command"] as? String, v["args"] as? [String] ?? [])
            }
            it.envKeys = ((v["env"] as? [String]) ?? t.keys(["mcp_servers", name, "env"])).sorted()
            it.configPath = configFile
            it.canToggle = true
            it.canRemove = true
            it.ref = ["kind": "server"]
            items.append(it)
        }

        for table in tables where table.path.count == 2 && table.path[0] == "plugins" {
            let pid = table.path[1]
            var it = Item(toolID: id, name: pid, kind: .plugin, scope: "global")
            it.enabled = t.values(table.path)["enabled"] as? Bool ?? true
            it.configPath = configFile
            it.canToggle = true
            it.canRemove = hasCLI
            it.ref = ["kind": "plugin"]
            items.append(it)
        }
        return items
    }

    /// Server name → plugin, from each installed plugin's `.mcp.json` / `mcp.json`
    /// (~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/).
    func pluginServers(installed: Set<String>) -> [String: String] {
        let cache = env.path(".codex/plugins/cache")
        let fm = FileManager.default
        var map: [String: String] = [:]
        for market in (try? fm.contentsOfDirectory(atPath: cache)) ?? [] {
            for plugin in (try? fm.contentsOfDirectory(atPath: "\(cache)/\(market)")) ?? [] {
                guard installed.contains("\(plugin)@\(market)") else { continue }
                for version in (try? fm.contentsOfDirectory(atPath: "\(cache)/\(market)/\(plugin)")) ?? [] {
                    for file in [".mcp.json", "mcp.json"] {
                        let path = "\(cache)/\(market)/\(plugin)/\(version)/\(file)"
                        guard env.exists(path), let j = try? JsonText(file: path) else { continue }
                        let names = (try? j.keys(at: ["mcpServers"])).flatMap { $0.isEmpty ? nil : $0 }
                            ?? (try? j.keys(at: [])) ?? []
                        for n in names where n != "mcpServers" { map[n] = plugin }
                    }
                }
            }
        }
        return map
    }

    /// Plugin servers run from ~/.codex/plugins/cache/<marketplace>/<plugin>/...
    static func pluginName(_ transport: [String: Any]) -> String? {
        for key in ["cwd", "command"] {
            guard let p = transport[key] as? String, let r = p.range(of: "/plugins/cache/") else { continue }
            let parts = p[r.upperBound...].split(separator: "/")
            if parts.count >= 2 { return String(parts[1]) }
        }
        return nil
    }

    public func setEnabled(_ item: Item, _ on: Bool) async throws {
        let path: [String]
        switch item.ref["kind"] {
        case "server": path = ["mcp_servers", item.name]
        case "plugin": path = ["plugins", item.name]
        default: throw ManagerError("\(item.name) can't be turned on/off here.")
        }
        var t = try toml()
        t.setBool("enabled", on, in: path)
        try SafeFileWriter.write(t.text, to: configFile)
    }

    public func remove(_ item: Item) async throws {
        switch item.ref["kind"] {
        case "server":
            if hasCLI {
                try await env.runner.check("codex", ["mcp", "remove", item.name])
            } else {
                var t = try toml()
                _ = t.removeTable(["mcp_servers", item.name])
                try SafeFileWriter.write(t.text, to: configFile)
            }
        case "plugin":
            try await env.runner.check("codex", ["plugin", "remove", item.name])
        default:
            throw ManagerError("\(item.name) can't be removed here.")
        }
    }
}
