import Foundation

public struct ShellResult: Sendable {
    public let status: Int32
    public let out: String
    public let err: String
    public var ok: Bool { status == 0 }
}

public protocol CommandRunner: Sendable {
    /// Full path of a CLI, or nil when it isn't installed.
    func find(_ name: String) -> String?
    func execute(_ exe: String, _ args: [String], cwd: String?, timeout: TimeInterval) async throws -> ShellResult
}

public extension CommandRunner {
    func run(_ name: String, _ args: [String], cwd: String? = nil, timeout: TimeInterval = 60) async throws -> ShellResult {
        guard let exe = find(name) else { throw ManagerError("\(name) is not installed (not found on PATH).") }
        return try await execute(exe, args, cwd: cwd, timeout: timeout)
    }

    /// Runs and throws with the tool's own message when it fails.
    func check(_ name: String, _ args: [String], cwd: String? = nil) async throws {
        let r = try await run(name, args, cwd: cwd)
        guard r.ok else {
            let msg = (r.err.isEmpty ? r.out : r.err).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ManagerError("\(name) \(args.joined(separator: " ")) failed: \(msg)")
        }
    }
}

/// Runs CLIs (claude, codex, gemini...). An app opened from Finder gets a tiny PATH,
/// so we look in the usual install folders and pass that PATH on (servers need node/uv/npx).
public struct Shell: CommandRunner {
    let searchPath: [String]

    public init(home: URL) {
        let h = home.path
        searchPath = ["\(h)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(h)/.npm-global/bin",
                      "\(h)/.bun/bin", "\(h)/.cargo/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    }

    public func find(_ name: String) -> String? {
        for dir in searchPath {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    public func execute(_ exe: String, _ args: [String], cwd: String?, timeout: TimeInterval) async throws -> ShellResult {
        // Output goes to temp files, not pipes: a full pipe would block the child forever.
        let tmp = FileManager.default.temporaryDirectory
        let outURL = tmp.appendingPathComponent("aitm-\(UUID().uuidString).out")
        let errURL = tmp.appendingPathComponent("aitm-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }
        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath.joined(separator: ":")
        env["NO_COLOR"] = "1"
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = outHandle
        p.standardError = errHandle

        let status: Int32 = try await withCheckedThrowingContinuation { cont in
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { cont.resume(throwing: error); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if p.isRunning { p.terminate() }
            }
        }
        try? outHandle.close()
        try? errHandle.close()
        let out = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        let err = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        return ShellResult(status: status, out: out, err: err)
    }
}
