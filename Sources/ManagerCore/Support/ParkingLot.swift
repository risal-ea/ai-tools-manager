import Foundation

/// "Turn off" for tools that have no on/off flag: the server's config text is moved out of the
/// tool's file into our own file, and moved back when you turn it on. Nothing is lost.
public struct ParkedEntry: Codable, Hashable, Sendable {
    public var toolID: String
    public var file: String        // the tool's config file
    public var path: [String]      // where it lived, e.g. ["mcpServers", "github"]
    public var raw: String         // its exact config text (JSON / YAML block / TOML block)
    public var parkedAt: Date
}

public final class ParkingLot: @unchecked Sendable {
    public let file: URL
    private let lock = NSLock()

    public init(file: URL) { self.file = file }

    public func all() -> [ParkedEntry] {
        lock.lock(); defer { lock.unlock() }
        return read()
    }

    public func entries(tool: String) -> [ParkedEntry] {
        all().filter { $0.toolID == tool }
    }

    public func park(_ entry: ParkedEntry) throws {
        lock.lock(); defer { lock.unlock() }
        var list = read().filter { !($0.toolID == entry.toolID && $0.file == entry.file && $0.path == entry.path) }
        list.append(entry)
        try save(list)
    }

    @discardableResult
    public func take(tool: String, file: String, path: [String]) throws -> ParkedEntry? {
        lock.lock(); defer { lock.unlock() }
        var list = read()
        guard let i = list.firstIndex(where: { $0.toolID == tool && $0.file == file && $0.path == path }) else { return nil }
        let e = list.remove(at: i)
        try save(list)
        return e
    }

    private func read() -> [ParkedEntry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([ParkedEntry].self, from: data)) ?? []
    }

    private func save(_ list: [ParkedEntry]) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let text = String(decoding: try enc.encode(list), as: UTF8.self)
        try SafeFileWriter.write(text, to: file.path)
        // Parked configs may hold API keys: only you may read the file.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
