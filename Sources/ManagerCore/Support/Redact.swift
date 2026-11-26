import Foundation

/// Hides secrets in what the window shows: we only ever show env/header *names*,
/// and mask values that look secret inside a command line or URL.
public enum Redact {
    static let secretWords = ["key", "token", "secret", "password", "passwd", "auth", "bearer", "credential"]

    static func looksSecret(_ name: String) -> Bool {
        let n = name.lowercased()
        return secretWords.contains { n.contains($0) }
    }

    /// `--api-key abc` / `--token=abc` / `KEY=abc` → value masked.
    public static func args(_ args: [String]) -> [String] {
        var out: [String] = []
        var maskNext = false
        for a in args {
            if maskNext { out.append("••••"); maskNext = false; continue }
            if let eq = a.firstIndex(of: "="), looksSecret(String(a[..<eq])) {
                out.append(String(a[...eq]) + "••••")
            } else if a.hasPrefix("-"), looksSecret(a) {
                out.append(a); maskNext = true
            } else if a.lowercased().hasPrefix("bearer ") {
                out.append("Bearer ••••")
            } else {
                out.append(url(a))
            }
        }
        return out
    }

    /// Masks a password in the URL and the values of secret-looking query params.
    public static func url(_ s: String) -> String {
        guard s.contains("://"), var c = URLComponents(string: s) else { return s }
        if c.password != nil { c.password = "••••" }
        if let items = c.queryItems {
            c.queryItems = items.map { looksSecret($0.name) ? URLQueryItem(name: $0.name, value: "••••") : $0 }
        }
        return (c.string ?? s).replacingOccurrences(of: "%E2%80%A2", with: "•")
    }

    public static func commandLine(_ command: String?, _ args: [String]) -> String? {
        guard let command, !command.isEmpty else { return nil }
        return ([command] + Self.args(args)).joined(separator: " ")
    }
}
