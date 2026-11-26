import Foundation
@testable import ManagerCore

/// A pretend CLI: answers with canned output and records what was run.
final class FakeRunner: CommandRunner, @unchecked Sendable {
    var installed: Set<String> = []
    var outputs: [String: String] = [:]     // "claude plugin list --json" → stdout
    var calls: [String] = []

    func find(_ name: String) -> String? { installed.contains(name) ? "/fake/\(name)" : nil }

    func execute(_ exe: String, _ args: [String], cwd: String?, timeout: TimeInterval) async throws -> ShellResult {
        let cmd = ([URL(fileURLWithPath: exe).lastPathComponent] + args).joined(separator: " ")
        calls.append(cmd)
        return ShellResult(status: 0, out: outputs[cmd] ?? "", err: "")
    }
}

/// A throwaway home folder.
struct TempHome {
    let url: URL
    let runner = FakeRunner()
    let env: ToolEnv

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("aitm-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        env = ToolEnv(home: url, runner: runner,
                      parking: ParkingLot(file: url.appendingPathComponent("support/parked.json")))
    }

    func write(_ relative: String, _ text: String) {
        let f = url.appendingPathComponent(relative)
        try! FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! text.write(to: f, atomically: true, encoding: .utf8)
    }

    func read(_ relative: String) -> String {
        (try? String(contentsOf: url.appendingPathComponent(relative), encoding: .utf8)) ?? ""
    }

    func backups(of relative: String) -> [String] {
        let f = url.appendingPathComponent(relative)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: f.deletingLastPathComponent().path)) ?? []
        return names.filter { $0.hasPrefix(f.lastPathComponent + SafeFileWriter.suffix) }
    }

    func cleanup() { try? FileManager.default.removeItem(at: url) }
}
