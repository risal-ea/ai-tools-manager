import Foundation

/// Just enough TOML for Codex's config.toml: find `[tables]`, read simple `key = value` lines,
/// set `enabled = true/false`, cut a table out (and put it back). Every other line stays as it was.
public struct TomlLite {
    public private(set) var lines: [String]
    public var text: String { lines.joined(separator: "\n") }

    public init(_ text: String) { lines = text.components(separatedBy: "\n") }

    public struct Table {
        public let path: [String]
        public let header: Int        // line of `[...]`
        public let end: Int           // first line after the table's body
    }

    public func tables() -> [Table] {
        var heads: [(Int, [String])] = []
        for (n, line) in lines.enumerated() {
            if let p = Self.headerPath(line) { heads.append((n, p)) }
        }
        return heads.enumerated().map { k, h in
            Table(path: h.1, header: h.0, end: k + 1 < heads.count ? heads[k + 1].0 : lines.count)
        }
    }

    public func table(_ path: [String]) -> Table? { tables().first { $0.path == path } }

    /// Simple values of a table: strings, bools, numbers, one-line string arrays.
    public func values(_ path: [String]) -> [String: Any] {
        guard let t = table(path) else { return [:] }
        var out: [String: Any] = [:]
        for line in lines[(t.header + 1)..<t.end] {
            guard let (k, v) = Self.keyValue(line) else { continue }
            out[k] = Self.parseValue(v)
        }
        return out
    }

    /// Key names only (for env tables / inline tables: we never read the values).
    public func keys(_ path: [String]) -> [String] {
        guard let t = table(path) else { return [] }
        return lines[(t.header + 1)..<t.end].compactMap { Self.keyValue($0)?.0 }
    }

    public mutating func setBool(_ key: String, _ value: Bool, in path: [String]) {
        let newLine = "\(key) = \(value)"
        guard let t = table(path) else {
            if lines.last?.isEmpty == false { lines.append("") }
            lines.append("[\(Self.formatPath(path))]")
            lines.append(newLine)
            return
        }
        for n in (t.header + 1)..<t.end where Self.keyValue(lines[n])?.0 == key {
            let indent = lines[n].prefix { $0 == " " || $0 == "\t" }
            lines[n] = indent + newLine
            return
        }
        lines.insert(newLine, at: t.header + 1)
    }

    /// Cuts out a table and its sub-tables (`[a.b]` + `[a.b.env]`); returns their text.
    public mutating func removeTable(_ path: [String]) -> String? {
        let all = tables().filter { $0.path.starts(with: path) }
        guard let first = all.first, let last = all.last else { return nil }
        var end = last.end
        // Don't take the blank line that separates it from the next table.
        while end > last.header + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
        let cut = lines[first.header..<end].joined(separator: "\n")
        lines.removeSubrange(first.header..<end)
        if first.header < lines.count, first.header > 0,
           lines[first.header].trimmingCharacters(in: .whitespaces).isEmpty,
           lines[first.header - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            lines.remove(at: first.header)
        }
        return cut
    }

    public mutating func appendBlock(_ block: String) {
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        lines.append("")
        lines.append(contentsOf: block.components(separatedBy: "\n"))
        lines.append("")
    }

    // MARK: - Parsing helpers

    static func headerPath(_ line: String) -> [String]? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("["), !t.hasPrefix("[["), let close = Self.closingBracket(t) else { return nil }
        let inner = String(t[t.index(after: t.startIndex)..<close])
        return splitDotted(inner)
    }

    static func closingBracket(_ t: String) -> String.Index? {
        var inQuote: Character?
        for i in t.indices {
            let c = t[i]
            if let q = inQuote { if c == q { inQuote = nil } }
            else if c == "\"" || c == "'" { inQuote = c }
            else if c == "]" { return i }
        }
        return nil
    }

    static func splitDotted(_ s: String) -> [String] {
        var parts: [String] = []
        var cur = ""
        var inQuote: Character?
        for c in s {
            if let q = inQuote {
                if c == q { inQuote = nil } else { cur.append(c) }
            } else if c == "\"" || c == "'" {
                inQuote = c
            } else if c == "." {
                parts.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""
            } else {
                cur.append(c)
            }
        }
        parts.append(cur.trimmingCharacters(in: .whitespaces))
        return parts
    }

    static func formatPath(_ path: [String]) -> String {
        path.map { p in
            p.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" } && !p.isEmpty
                ? p : "\"\(p.replacingOccurrences(of: "\"", with: "\\\""))\""
        }.joined(separator: ".")
    }

    static func keyValue(_ line: String) -> (String, String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.hasPrefix("#"), !t.hasPrefix("["), let eq = t.firstIndex(of: "=") else { return nil }
        var key = t[..<eq].trimmingCharacters(in: .whitespaces)
        if key.count >= 2, key.first == "\"" || key.first == "'" { key = String(key.dropFirst().dropLast()) }
        guard !key.isEmpty else { return nil }
        return (key, t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces))
    }

    static func parseValue(_ v: String) -> Any {
        if v == "true" { return true }
        if v == "false" { return false }
        if v.hasPrefix("\"") || v.hasPrefix("'") { return unquote(v) }
        if v.hasPrefix("[") {
            let inner = v.dropFirst().prefix { $0 != "]" }
            return splitTopLevel(String(inner)).map { unquote($0.trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.isEmpty }
        }
        if v.hasPrefix("{") {
            // Inline table: names only.
            return splitTopLevel(String(v.dropFirst().dropLast())).compactMap { part -> String? in
                guard let eq = part.firstIndex(of: "=") else { return nil }
                return unquote(part[..<eq].trimmingCharacters(in: .whitespaces))
            }
        }
        return Double(v.split(separator: "#").first?.trimmingCharacters(in: .whitespaces) ?? "") ?? v
    }

    static func unquote(_ s: String) -> String {
        guard let q = s.first, q == "\"" || q == "'" else { return s }
        var out = ""
        var escaped = false
        for c in s.dropFirst() {
            if escaped { out.append(c); escaped = false; continue }
            if c == "\\" && q == "\"" { escaped = true; continue }
            if c == q { break }
            out.append(c)
        }
        return out
    }

    static func splitTopLevel(_ s: String) -> [String] {
        var parts: [String] = []
        var cur = ""
        var inQuote: Character?
        for c in s {
            if let q = inQuote { if c == q { inQuote = nil }; cur.append(c); continue }
            if c == "\"" || c == "'" { inQuote = c; cur.append(c); continue }
            if c == "," { parts.append(cur); cur = ""; continue }
            cur.append(c)
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(cur) }
        return parts
    }
}
