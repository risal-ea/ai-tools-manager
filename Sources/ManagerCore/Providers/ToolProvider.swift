import Foundation

/// One adapter per AI tool. The window only talks to this.
public protocol ToolProvider: Sendable {
    var id: String { get }
    var name: String { get }
    /// Changes only take effect after the tool restarts (desktop apps / editors).
    var needsRestart: Bool { get }
    /// Its config file, app or CLI exists on this Mac.
    func isInstalled() -> Bool
    /// MCP servers + plugins/extensions, as written in its config.
    func load() async throws -> [Item]
    /// Slow (starts the servers): run after `load`, in the background.
    func health(for items: [Item]) async -> HealthReport
    func setEnabled(_ item: Item, _ on: Bool) async throws
    func remove(_ item: Item) async throws
}

public extension ToolProvider {
    var needsRestart: Bool { false }
    func health(for items: [Item]) async -> HealthReport { HealthReport() }
}

/// Where providers look for files and run commands. Tests swap in a temp folder and a fake runner.
public struct ToolEnv: Sendable {
    public let home: URL
    public let runner: CommandRunner
    public let parking: ParkingLot

    public init(home: URL, runner: CommandRunner, parking: ParkingLot) {
        self.home = home
        self.runner = runner
        self.parking = parking
    }

    public static func live() -> ToolEnv {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent("Library/Application Support/AIToolsManager")
        return ToolEnv(home: home, runner: Shell(home: home),
                           parking: ParkingLot(file: support.appendingPathComponent("parked.json")))
    }

    public func path(_ relative: String) -> String {
        home.appendingPathComponent(relative).path
    }

    public func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
