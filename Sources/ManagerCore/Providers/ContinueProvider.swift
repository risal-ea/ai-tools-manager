import Foundation
import Yams

/// Continue: `mcpServers:` list in ~/.continue/config.yaml, plus one-file blocks in ~/.continue/mcpServers/.
/// No on/off flag, so "off" parks the YAML block (or moves the file aside).
public struct ContinueProvider: ToolProvider {
    let env: ToolEnv
    public init(env: ToolEnv) { self.env = env }

    public let id = "continue"
    public let name = "Continue"
    public var needsRestart: Bool { true }

    var dir: String { env.path(".continue") }
    var configFile: String { "\(dir)/config.yaml" }
    var blocksDir: String { "\(dir)/mcpServers" }
    var parkedDir: String { env.parking.file.deletingLastPathComponent().appendingPathComponent("parked-files/continue").path }

    public func isInstalled() -> Bool { env.exists(dir) }

    public func load() async throws -> [Item] {
        var items: [Item] = []
        let parked = env.parking.entries(tool: id)

        if env.exists(configFile) {
            let text = try String(contentsOfFile: configFile, encoding: .utf8)
            for block in Self.blocks(text) {
                var it = Item(toolID: id, name: block.name, kind: .mcp, scope: "config.yaml")
                ServerConfig.fill(&it, from: block.config)
                it.configPath = configFile
                it.canToggle = true
                it.canRemove = true
                it.ref = ["kind": "block"]
                items.append(it)
            }
        }
        for p in parked where p.path.first == "block" {
            var it = Item(toolID: id, name: p.path.last ?? "?", kind: .mcp, scope: "config.yaml")
            ServerConfig.fill(&it, from: Self.blocks("mcpServers:\n" + p.raw).first?.config)
            it.enabled = false
            it.configPath = configFile
            it.canToggle = true
            it.canRemove = true
            it.ref = ["kind": "block", "parked": "1"]
            items.append(it)
        }

        let files = ((try? FileManager.default.contentsOfDirectory(atPath: blocksDir)) ?? [])
            .filter { $0.hasSuffix(".yaml") || $0.hasSuffix(".yml") || $0.hasSuffix(".json") }.sorted()
        for f in files {
            let path = "\(blocksDir)/\(f)"
            items.append(fileItem(path: path, enabled: true))
        }
        for p in parked where p.path.first == "file" {
            var it = fileItem(path: p.raw, enabled: false, shownPath: p.path.last)
            it.ref["parked"] = "1"
            items.append(it)
        }
        return items
    }

    func fileItem(path: String, enabled: Bool, shownPath: String? = nil) -> Item {
        let fileName = URL(fileURLWithPath: shownPath ?? path).lastPathComponent
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let loaded = (try? Yams.load(yaml: text)) as? [String: Any]
        let server = (loaded?["mcpServers"] as? [[String: Any]])?.first ?? loaded
        let name = server?["name"] as? String ?? fileName
        var it = Item(toolID: id, name: name, kind: .mcp, scope: "mcpServers/\(fileName)")
        ServerConfig.fill(&it, from: server)
        it.enabled = enabled
        it.configPath = shownPath ?? path
        it.canToggle = true
        it.canRemove = true
        it.ref = ["kind": "file", "path": shownPath ?? path]
        return it
    }

    // MARK: - YAML blocks

    struct Block {
        let name: String
        let config: [String: Any]
        let lines: Range<Int>    // the item's lines, `- name: ...` to the last line of the item
    }

    /// Finds each `- ...` item under the top-level `mcpServers:` key, with its exact lines.
    static func blocks(_ text: String) -> [Block] {
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.hasPrefix("mcpServers:") }) else { return [] }
        var end = lines.count
        for n in (start + 1)..<lines.count {
            let l = lines[n]
            if !l.trimmingCharacters(in: .whitespaces).isEmpty, !l.hasPrefix(" "), !l.hasPrefix("-"), !l.hasPrefix("#") {
                end = n; break
            }
        }
        // Item starts: lines whose first non-space is "- " at the first item's indent.
        var starts: [Int] = []
        var indent: Int?
        for n in (start + 1)..<end {
            let l = lines[n]
            let lead = l.prefix { $0 == " " }.count
            guard l.dropFirst(lead).hasPrefix("- ") || l.dropFirst(lead) == "-" else { continue }
            if indent == nil { indent = lead }
            if lead == indent { starts.append(n) }
        }
        var out: [Block] = []
        for (k, s) in starts.enumerated() {
            var e = k + 1 < starts.count ? starts[k + 1] : end
            while e > s + 1, lines[e - 1].trimmingCharacters(in: .whitespaces).isEmpty { e -= 1 }
            let chunk = lines[s..<e].joined(separator: "\n")
            guard let arr = (try? Yams.load(yaml: chunk)) as? [[String: Any]], let cfg = arr.first,
                  let name = cfg["name"] as? String else { continue }
            out.append(Block(name: name, config: cfg, lines: s..<e))
        }
        return out
    }

    // MARK: - Change

    public func setEnabled(_ item: Item, _ on: Bool) async throws {
        switch item.ref["kind"] {
        case "block":
            let path = ["block", item.name]
            if on {
                guard let e = env.parking.entries(tool: id).first(where: { $0.path == path }) else { return }
                var text = env.exists(configFile) ? try String(contentsOfFile: configFile, encoding: .utf8) : ""
                var lines = text.components(separatedBy: "\n")
                if let last = Self.blocks(text).last {
                    lines.insert(contentsOf: e.raw.components(separatedBy: "\n"), at: last.lines.upperBound)
                } else if let k = lines.firstIndex(where: { $0.hasPrefix("mcpServers:") }) {
                    lines[k] = "mcpServers:"   // e.g. `mcpServers: []`
                    lines.insert(contentsOf: e.raw.components(separatedBy: "\n"), at: k + 1)
                } else {
                    if lines.last?.isEmpty == false { lines.append("") }
                    lines.append("mcpServers:")
                    lines.append(contentsOf: e.raw.components(separatedBy: "\n"))
                }
                text = lines.joined(separator: "\n")
                try SafeFileWriter.write(text, to: configFile)
                try env.parking.take(tool: id, file: configFile, path: path)
            } else {
                let text = try String(contentsOfFile: configFile, encoding: .utf8)
                guard let b = Self.blocks(text).first(where: { $0.name == item.name }) else { return }
                var lines = text.components(separatedBy: "\n")
                let raw = lines[b.lines].joined(separator: "\n")
                try env.parking.park(ParkedEntry(toolID: id, file: configFile, path: path, raw: raw, parkedAt: Date()))
                lines.removeSubrange(b.lines)
                try SafeFileWriter.write(lines.joined(separator: "\n"), to: configFile)
            }
        case "file":
            guard let original = item.ref["path"] else { return }
            let fm = FileManager.default
            if on {
                guard let e = env.parking.entries(tool: id).first(where: { $0.path == ["file", original] }) else { return }
                try fm.moveItem(atPath: e.raw, toPath: original)
                try env.parking.take(tool: id, file: original, path: ["file", original])
            } else {
                try fm.createDirectory(atPath: parkedDir, withIntermediateDirectories: true)
                let dest = "\(parkedDir)/\(UUID().uuidString)-\(URL(fileURLWithPath: original).lastPathComponent)"
                try fm.moveItem(atPath: original, toPath: dest)
                try env.parking.park(ParkedEntry(toolID: id, file: original, path: ["file", original], raw: dest, parkedAt: Date()))
            }
        default:
            throw ManagerError("\(item.name) can't be turned on/off here.")
        }
    }

    public func remove(_ item: Item) async throws {
        switch item.ref["kind"] {
        case "block":
            if item.ref["parked"] != nil {
                try env.parking.take(tool: id, file: configFile, path: ["block", item.name])
                return
            }
            let text = try String(contentsOfFile: configFile, encoding: .utf8)
            guard let b = Self.blocks(text).first(where: { $0.name == item.name }) else { return }
            var lines = text.components(separatedBy: "\n")
            lines.removeSubrange(b.lines)
            try SafeFileWriter.write(lines.joined(separator: "\n"), to: configFile)
        case "file":
            guard let original = item.ref["path"] else { return }
            if item.ref["parked"] != nil, let e = try env.parking.take(tool: id, file: original, path: ["file", original]) {
                try SafeFileWriter.remove(e.raw)
            } else {
                try SafeFileWriter.remove(original)
            }
        default:
            throw ManagerError("\(item.name) can't be removed here.")
        }
    }
}
