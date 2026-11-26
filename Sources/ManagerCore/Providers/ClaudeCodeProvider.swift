import Foundation

/// Claude Code: servers in ~/.claude.json (global + per project), shared `.mcp.json` files in projects,
/// plugins (with the servers they bring), and the claude.ai connectors (seen through `claude mcp list`).
public struct ClaudeCodeProvider: ToolProvider {
    let env: ToolEnv
    public init(env: ToolEnv) { self.env = env }

    public let id = "claude-code"
    public let name = "Claude Code"
    public var needsRestart: Bool { true }   // running sessions keep their servers until restarted

    var configFile: String { env.path(".claude.json") }
    var hasCLI: Bool { env.runner.find("claude") != nil }

    public func isInstalled() -> Bool { env.exists(configFile) || hasCLI }

    // MARK: - Load

    public func load() async throws -> [Item] {
        var items: [Item] = []
        let root: [String: Any] = env.exists(configFile)
            ? ((try JsonText(file: configFile).value(at: []) as? [String: Any]) ?? [:]) : [:]

        // Global ("user") servers.
        let user = root["mcpServers"] as? [String: Any] ?? [:]
        for name in user.keys.sorted() {
            var it = Item(toolID: id, name: name, kind: .mcp, scope: "global")
            ServerConfig.fill(&it, from: user[name])
            it.configPath = configFile
            it.canToggle = true
            it.canRemove = true
            it.ref = ["kind": "user"]
            items.append(it)
        }
        for p in env.parking.entries(tool: id) where p.path.count == 2 && p.path[0] == "mcpServers" && user[p.path[1]] == nil {
            var it = Item(toolID: id, name: p.path[1], kind: .mcp, scope: "global")
            ServerConfig.fill(&it, from: try? JsonText(p.raw).value(at: []))
            it.enabled = false
            it.configPath = configFile
            it.canToggle = true
            it.canRemove = true
            it.note = "Turned off by AI Tools Manager: its config is kept aside and goes back when you turn it on."
            it.ref = ["kind": "user", "parked": "1"]
            items.append(it)
        }

        // Per-project servers ("local") + the project's shared .mcp.json.
        let projects = root["projects"] as? [String: Any] ?? [:]
        for path in projects.keys.sorted() {
            let proj = projects[path] as? [String: Any] ?? [:]
            let disabled = Set(proj["disabledMcpServers"] as? [String] ?? [])
            let local = proj["mcpServers"] as? [String: Any] ?? [:]
            for name in local.keys.sorted() {
                var it = Item(toolID: id, name: name, kind: .mcp, scope: "project: \(path)")
                ServerConfig.fill(&it, from: local[name])
                it.enabled = !disabled.contains(name)
                it.configPath = configFile
                it.canToggle = true
                it.canRemove = true
                it.ref = ["kind": "local", "project": path]
                items.append(it)
            }

            let shared = "\(path)/.mcp.json"
            guard env.exists(shared), let j = try? JsonText(file: shared),
                  let servers = try? j.value(at: ["mcpServers"]) as? [String: Any] else { continue }
            let on = Set(proj["enabledMcpjsonServers"] as? [String] ?? [])
            let off = Set(proj["disabledMcpjsonServers"] as? [String] ?? [])
            let all = proj["enableAllProjectMcpServers"] as? Bool ?? false
            for name in servers.keys.sorted() {
                var it = Item(toolID: id, name: name, kind: .mcp, scope: "shared: \(path)")
                ServerConfig.fill(&it, from: servers[name])
                it.configPath = shared
                it.canToggle = true
                it.canRemove = false
                it.ref = ["kind": "shared", "project": path]
                if off.contains(name) {
                    it.enabled = false
                } else if on.contains(name) || all {
                    it.enabled = true
                } else {
                    it.enabled = false
                    it.health = .pending
                    it.note = "Not approved yet in this project. Turning it on approves it."
                }
                it.note = [it.note, "Shared through the project's .mcp.json (in its git repo): edit that file to remove it."]
                    .compactMap { $0 }.joined(separator: " ")
                items.append(it)
            }
        }

        items += try await plugins()
        return items
    }

    func plugins() async throws -> [Item] {
        var items: [Item] = []
        if hasCLI, let r = try? await env.runner.run("claude", ["plugin", "list", "--json"]), r.ok,
           let list = try? JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [[String: Any]] {
            for p in list {
                guard let pid = p["id"] as? String else { continue }
                let scope = p["scope"] as? String ?? "user"
                let enabled = p["enabled"] as? Bool ?? false
                let short = pid.split(separator: "@").first.map(String.init) ?? pid
                var it = Item(toolID: id, name: pid, kind: .plugin, scope: scope == "user" ? "global" : scope)
                it.enabled = enabled
                it.target = p["version"].map { "version \($0)" }
                it.configPath = p["installPath"] as? String
                it.canToggle = true
                it.canRemove = true
                it.ref = ["id": pid, "scope": scope]
                items.append(it)

                for (sname, cfg) in (p["mcpServers"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
                    var s = Item(toolID: id, name: sname, kind: .mcp, scope: "plugin: \(short)")
                    ServerConfig.fill(&s, from: cfg)
                    s.enabled = enabled
                    s.configPath = p["installPath"] as? String
                    s.note = "Comes with the plugin \(pid): turn the plugin off to stop it."
                    s.ref = ["kind": "plugin", "plugin": short]
                    items.append(s)
                }
            }
            return items
        }

        // No CLI: read the files (names + on/off only).
        let settings = env.path(".claude/settings.json")
        let enabledMap = (try? JsonText(file: settings).value(at: ["enabledPlugins"]) as? [String: Any]) ?? [:]
        let installed = env.path(".claude/plugins/installed_plugins.json")
        let ids = (try? JsonText(file: installed).keys(at: ["plugins"])) ?? []
        for pid in ids {
            var it = Item(toolID: id, name: pid, kind: .plugin, scope: "global")
            it.enabled = enabledMap[pid] as? Bool ?? false
            it.configPath = installed
            it.note = "Install the claude CLI to turn plugins on/off or remove them here."
            items.append(it)
        }
        return items
    }

    // MARK: - Health

    /// `claude mcp list` starts every server and prints one line each:
    ///   `name: target - ✔ Connected` / `- ! Needs authentication` / `- ✘ Failed to connect — why`
    public func health(for items: [Item]) async -> HealthReport {
        var report = HealthReport()
        guard hasCLI,
              let r = try? await env.runner.run("claude", ["mcp", "list"], cwd: env.home.path, timeout: 120) else { return report }
        let home = env.home.path
        for line in r.out.components(separatedBy: "\n") {
            guard let parsed = Self.parseHealthLine(line) else { continue }
            let (name, target, health) = parsed
            if name.hasPrefix("claude.ai ") {
                var it = Item(toolID: id, name: String(name.dropFirst("claude.ai ".count)), kind: .mcp, scope: "claude.ai")
                it.target = Redact.url(target)
                it.transport = "http"
                it.health = health
                it.note = "A claude.ai connector: manage it at claude.ai → Settings → Connectors."
                it.ref = ["kind": "cloud", "link": "https://claude.ai/settings/connectors"]
                report.extraItems.append(it)
            } else if name.hasPrefix("plugin:") {
                let parts = name.split(separator: ":", maxSplits: 2).map(String.init)
                guard parts.count == 3 else { continue }
                if let it = items.first(where: { $0.kind == .mcp && $0.scope == "plugin: \(parts[1])" && $0.name == parts[2] }) {
                    report.byItemID[it.id] = health
                }
            } else if let it = items.first(where: { $0.kind == .mcp && $0.name == name && $0.scope == "global" })
                        ?? items.first(where: { $0.kind == .mcp && $0.name == name && $0.ref["project"] == home }) {
                report.byItemID[it.id] = health
            }
        }
        return report
    }

    static func parseHealthLine(_ line: String) -> (String, String, Health)? {
        let symbols: [(String, (String) -> Health)] = [
            (" - ✔", { _ in .connected }),
            (" - !", { _ in .needsAuth }),
            (" - ⏸", { _ in .pending }),
            (" - ✘", { rest in
                let why = rest.components(separatedBy: "—").dropFirst().joined(separator: "—")
                    .trimmingCharacters(in: .whitespaces)
                return .failed(String((why.isEmpty ? rest : why).prefix(160)))
            }),
        ]
        guard let colon = line.range(of: ": ") else { return nil }
        let name = String(line[..<colon.lowerBound])
        let after = String(line[colon.upperBound...])
        for (sym, make) in symbols {
            guard let r = after.range(of: sym, options: .backwards) else { continue }
            var target = String(after[..<r.lowerBound])
            if target.hasSuffix(" (HTTP)") || target.hasSuffix(" (SSE)") {
                target = String(target[..<target.lastIndex(of: "(")!]).trimmingCharacters(in: .whitespaces)
            }
            let rest = String(after[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (name, target, make(rest))
        }
        return nil
    }

    // MARK: - Change

    public func setEnabled(_ item: Item, _ on: Bool) async throws {
        if item.kind == .plugin, let pid = item.ref["id"] {
            try await env.runner.check("claude", ["plugin", on ? "enable" : "disable", pid, "-s", item.ref["scope"] ?? "user"])
            return
        }
        switch item.ref["kind"] {
        case "user":
            try await parkUser(item.name, on: on)
        case "local":
            guard let p = item.ref["project"] else { return }
            try editList(["projects", p, "disabledMcpServers"], item.name, add: !on)
        case "shared":
            guard let p = item.ref["project"] else { return }
            try editList(["projects", p, "enabledMcpjsonServers"], item.name, add: on)
            try editList(["projects", p, "disabledMcpjsonServers"], item.name, add: !on)
        default:
            throw ManagerError("\(item.name) can't be turned on/off here.")
        }
    }

    public func remove(_ item: Item) async throws {
        if item.kind == .plugin, let pid = item.ref["id"] {
            try await env.runner.check("claude", ["plugin", "uninstall", pid, "-s", item.ref["scope"] ?? "user"])
            return
        }
        switch item.ref["kind"] {
        case "user":
            if item.ref["parked"] != nil {
                try env.parking.take(tool: id, file: configFile, path: ["mcpServers", item.name])
            } else if hasCLI {
                try await env.runner.check("claude", ["mcp", "remove", item.name, "-s", "user"], cwd: env.home.path)
            } else {
                try removeKey(["mcpServers", item.name])
            }
        case "local":
            guard let p = item.ref["project"] else { return }
            if hasCLI && env.exists(p) {
                try await env.runner.check("claude", ["mcp", "remove", item.name, "-s", "local"], cwd: p)
            } else {
                try removeKey(["projects", p, "mcpServers", item.name])
            }
        default:
            throw ManagerError("\(item.name) can't be removed here.")
        }
    }

    func parkUser(_ name: String, on: Bool) async throws {
        let path = ["mcpServers", name]
        var j = try JsonText(file: configFile)
        if on {
            guard let e = env.parking.entries(tool: id).first(where: { $0.path == path }) else { return }
            try j.set(e.raw, at: path)
            try SafeFileWriter.write(j.text, to: configFile)
            try env.parking.take(tool: id, file: configFile, path: path)
        } else {
            guard let raw = try j.raw(at: path) else { return }
            try env.parking.park(ParkedEntry(toolID: id, file: configFile, path: path, raw: raw, parkedAt: Date()))
            try j.remove(at: path)
            do { try SafeFileWriter.write(j.text, to: configFile) } catch {
                _ = try? env.parking.take(tool: id, file: configFile, path: path)
                throw error
            }
        }
    }

    func editList(_ path: [String], _ name: String, add: Bool) throws {
        var j = try JsonText(file: configFile)
        var list = (try j.value(at: path) as? [String]) ?? []
        let had = list.contains(name)
        if add && !had { list.append(name) }
        if !add && had { list.removeAll { $0 == name } }
        guard add != had else { return }   // already as wanted
        try j.set(try JsonText.encode(list), at: path)
        try SafeFileWriter.write(j.text, to: configFile)
    }

    func removeKey(_ path: [String]) throws {
        var j = try JsonText(file: configFile)
        if try j.remove(at: path) { try SafeFileWriter.write(j.text, to: configFile) }
    }
}
