import Foundation

/// The only way this app writes a tool's config file:
/// 1. copy the current file to `<file>.aitm-bak-<time>` (keeps our newest 3; never touches other backups),
/// 2. write the new text to a temp file next to it,
/// 3. swap it in with one rename, so the tool never sees a half-written file.
public enum SafeFileWriter {
    public static let keepBackups = 3
    public static let suffix = ".aitm-bak-"

    @discardableResult
    public static func write(_ text: String, to path: String) throws -> String? {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var backup: String?
        if fm.fileExists(atPath: path) {
            let stamp = Self.stamp()
            let bak = "\(path)\(suffix)\(stamp)"
            try? fm.removeItem(atPath: bak)
            try fm.copyItem(atPath: path, toPath: bak)
            backup = bak
            prune(path)
        }

        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).aitm-\(UUID().uuidString)")
        try Data(text.utf8).write(to: tmp)
        if fm.fileExists(atPath: path) {
            // Keep the original file's permissions (some configs are 600).
            if let attrs = try? fm.attributesOfItem(atPath: path), let perms = attrs[.posixPermissions] {
                try? fm.setAttributes([.posixPermissions: perms], ofItemAtPath: tmp.path)
            }
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: url)
        }
        return backup
    }

    /// Moves a file away (to a backup) instead of deleting it.
    public static func remove(_ path: String) throws {
        let bak = "\(path)\(suffix)\(stamp())"
        try FileManager.default.moveItem(atPath: path, toPath: bak)
        prune(path)
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f.string(from: Date())
    }

    static func prune(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + suffix
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        // Only our own backups: prefix + exactly our stamp (yyyyMMdd-HHmmss-SSS). The stamp sorts by time.
        let backups = names.filter { name in
            guard name.hasPrefix(prefix) else { return false }
            let stamp = name.dropFirst(prefix.count)
            return stamp.count == 19 && stamp.allSatisfy { $0.isNumber || $0 == "-" }
        }.sorted()
        for old in backups.dropLast(keepBackups) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(old))
        }
    }
}
