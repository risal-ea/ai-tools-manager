import Foundation

/// A tool's own on/off flag, when it has one: Cline/Roo `"disabled": true`, OpenCode `"enabled": false`.
public struct OffFlag: Sendable {
    public let key: String
    public let offValue: Bool
    public init(_ key: String, offValue: Bool) { self.key = key; self.offValue = offValue }
}

/// Settings for one tool that keeps its MCP servers in a JSON file.
public struct JsonToolSpec: Sendable {
    public var id: String
    public var name: String
    /// (label, path relative to home). Every one that exists is read.
    public var files: [(label: String, path: String)]
    /// Where the servers are in the file, e.g. ["mcpServers"].
    public var key: [String]
    /// nil = no flag: "off" parks the server (see ParkingLot).
    public var flag: OffFlag? = nil
    /// Any of these existing means "installed" (absolute app paths).
    public var apps: [String] = []
    public var cli: String? = nil
    public var needsRestart = true
    /// A folder of extensions to list (read-only), relative to home.
    public var extensionsDir: String? = nil
    public var extensionsNote: String? = nil
}

public struct JsonMcpProvider: ToolProvider {
    public let spec: JsonToolSpec
    let env: ToolEnv

    public init(_ spec: JsonToolSpec, env: ToolEnv) {
        self.spec = spec
        self.env = env
    }

    public var id: String { spec.id }
    public var name: String { spec.name }
    public var needsRestart: Bool { spec.needsRestart }

    public func isInstalled() -> Bool {
        spec.files.contains { env.exists(env.path($0.path)) }
            || spec.apps.contains { env.exists($0) || env.exists(env.path("Applications/" + URL(fileURLWithPath: $0).lastPathComponent)) }
            || (spec.cli.map { env.runner.find($0) != nil } ?? false)
    }

    func scope(_ label: String) -> String { spec.files.count == 1 ? "global" : label }

    public func load() async throws -> [Item] {
        var items: [Item] = []
        let parked = env.parking.entries(tool: id)

        for f in spec.files {
            let file = env.path(f.path)
            var names = Set<String>()
            if env.exists(file) {
                let j = try JsonText(file: file)
                let servers = (try j.value(at: spec.key) as? [String: Any]) ?? [:]
                for name in try j.keys(at: spec.key) {
                    var it = Item(toolID: id, name: name, kind: .mcp, scope: scope(f.label))
                    ServerConfig.fill(&it, from: servers[name])
                    if let flag = spec.flag, let d = servers[name] as? [String: Any], let v = d[flag.key] as? Bool {
                        it.enabled = v != flag.offValue
                    }
                    it.configPath = file
                    it.canToggle = true
                    it.canRemove = true
                    it.ref = ["file": file]
                    items.append(it)
                    names.insert(name)
                }
            }
            for p in parked where p.file == file && !names.contains(p.path.last ?? "") {
                var it = Item(toolID: id, name: p.path.last ?? "?", kind: .mcp, scope: scope(f.label))
                ServerConfig.fill(&it, from: try? JsonText(p.raw).value(at: []))
                it.enabled = false
                it.configPath = file
                it.canToggle = true
                it.canRemove = true
                it.note = "Turned off by AI Tools Manager: its config is kept aside and goes back when you turn it on."
                it.ref = ["file": file, "parked": "1"]
                items.append(it)
            }
        }

        if let dir = spec.extensionsDir {
            let full = env.path(dir)
            let subs = (try? FileManager.default.contentsOfDirectory(atPath: full)) ?? []
            for s in subs.sorted() where !s.hasPrefix(".") {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: "\(full)/\(s)", isDirectory: &isDir), isDir.boolValue else { continue }
                var it = Item(toolID: id, name: s, kind: .extension, scope: "global")
                it.configPath = "\(full)/\(s)"
                it.note = spec.extensionsNote
                items.append(it)
            }
        }
        return items
    }

    public func setEnabled(_ item: Item, _ on: Bool) async throws {
        guard let file = item.ref["file"] else { throw ManagerError("Can't change \(item.name).") }
        let path = spec.key + [item.name]

        if let flag = spec.flag {
            var j = try JsonText(file: file)
            if on && flag.offValue {
                try j.remove(at: path + [flag.key])              // "disabled": true → gone
            } else {
                try j.set(String(on ? !flag.offValue : flag.offValue), at: path + [flag.key])
            }
            try SafeFileWriter.write(j.text, to: file)
            return
        }

        if on {
            guard let entry = env.parking.entries(tool: id).first(where: { $0.file == file && $0.path == path }) else { return }
            var j = env.exists(file) ? try JsonText(file: file) : JsonText("{}")
            try j.set(entry.raw, at: path)
            try SafeFileWriter.write(j.text, to: file)
            try env.parking.take(tool: id, file: file, path: path)
        } else {
            var j = try JsonText(file: file)
            guard let raw = try j.raw(at: path) else { return }
            // Keep a copy first, so nothing is lost if writing the file fails.
            try env.parking.park(ParkedEntry(toolID: id, file: file, path: path, raw: raw, parkedAt: Date()))
            try j.remove(at: path)
            do { try SafeFileWriter.write(j.text, to: file) } catch {
                _ = try? env.parking.take(tool: id, file: file, path: path)
                throw error
            }
        }
    }

    public func remove(_ item: Item) async throws {
        guard let file = item.ref["file"] else { throw ManagerError("Can't remove \(item.name).") }
        let path = spec.key + [item.name]
        if item.ref["parked"] != nil {
            try env.parking.take(tool: id, file: file, path: path)
            return
        }
        var j = try JsonText(file: file)
        if try j.remove(at: path) {
            try SafeFileWriter.write(j.text, to: file)
        }
    }
}
