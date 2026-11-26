import Foundation

/// Reads and edits a JSON (or JSONC: comments + trailing commas, like Zed/VS Code) file
/// while keeping every other byte as it was: spacing, key order, comments, numbers.
/// An edit changes only the text of the one entry it touches.
public struct JsonText {
    public private(set) var bytes: [UInt8]
    public var text: String { String(decoding: bytes, as: UTF8.self) }

    public init(_ text: String) { bytes = Array(text.utf8) }

    public init(file path: String) throws {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw ManagerError("Can't read \(path)")
        }
        bytes = Array(data)
    }

    // MARK: - Reading

    /// The value at a key path, as Foundation types ([String: Any], [Any], String, Double, Bool, NSNull).
    public func value(at path: [String]) throws -> Any? {
        guard let n = try node(at: path) else { return nil }
        return n.foundation()
    }

    /// Keys of the object at `path`, in file order.
    public func keys(at path: [String]) throws -> [String] {
        guard let n = try node(at: path), n.kind == .object else { return [] }
        var seen = Set<String>()
        return n.members.map(\.key).filter { seen.insert($0).inserted }
    }

    /// The exact text of the value at `path` (used to park a server's config untouched).
    public func raw(at path: [String]) throws -> String? {
        guard let n = try node(at: path) else { return nil }
        return String(decoding: bytes[n.start..<n.end], as: UTF8.self)
    }

    public func validate() throws { _ = try parse() }

    // MARK: - Editing

    /// Sets `path` to the JSON text `raw`. Missing parent objects are created.
    public mutating func set(_ raw: String, at path: [String]) throws {
        precondition(!path.isEmpty)
        var check = Parser(Array(raw.utf8))
        _ = try check.document()   // `raw` must be valid JSON itself
        let root = try parse()
        guard root.kind == .object else { throw ManagerError("The file's top level is not an object.") }

        var node = root
        var depth = 0
        while depth < path.count - 1 {
            guard let m = node.members.last(where: { $0.key == path[depth] }) else { break }
            guard m.value.kind == .object else {
                throw ManagerError("\(path[0...depth].joined(separator: ".")) is not an object.")
            }
            node = m.value
            depth += 1
        }
        if depth == path.count - 1, let m = node.members.last(where: { $0.key == path[depth] }) {
            replace(m.value.start..<m.value.end, with: raw)
        } else {
            var value = raw
            for key in path[(depth + 1)...].reversed() { value = "{\(Self.quote(key)): \(value)}" }
            insert(key: path[depth], raw: value, into: node)
        }
        try validate()
    }

    /// Removes the entry at `path`. Returns false when it isn't there.
    @discardableResult
    public mutating func remove(at path: [String]) throws -> Bool {
        precondition(!path.isEmpty)
        guard let parent = try node(at: Array(path.dropLast())), parent.kind == .object,
              let i = parent.members.lastIndex(where: { $0.key == path.last! }) else { return false }
        let m = parent.members[i]
        let range: Range<Int>
        if i > 0 {
            range = parent.members[i - 1].value.end..<m.value.end          // ", "key": value"
        } else if parent.members.count > 1 {
            range = m.keyStart..<parent.members[1].keyStart                  // ""key": value, "
        } else {
            range = (parent.start + 1)..<(parent.end - 1)                    // leaves "{}"
        }
        replace(range, with: "")
        try validate()
        return true
    }

    public static func quote(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])
        let arr = String(decoding: data, as: UTF8.self)
        return String(arr.dropFirst().dropLast())
    }

    /// Foundation value → JSON text (for small values we write, like a list of names).
    public static func encode(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Internals

    private mutating func replace(_ r: Range<Int>, with s: String) {
        bytes.replaceSubrange(r, with: Array(s.utf8))
    }

    private mutating func insert(key: String, raw: String, into obj: Node) {
        let member = "\(Self.quote(key)): \(raw)"
        if let last = obj.members.last {
            let indent = lineIndent(at: last.keyStart)
            let sep = indent == nil ? ", " : ",\n" + indent!
            replace(last.value.end..<last.value.end, with: sep + member)
        } else {
            let outer = lineIndent(at: obj.start) ?? ""
            let inner = outer + "  "
            replace((obj.start + 1)..<(obj.end - 1), with: "\n\(inner)\(member)\n\(outer)")
        }
    }

    /// The leading whitespace of the line, if `offset` is the first thing on it.
    private func lineIndent(at offset: Int) -> String? {
        var i = offset - 1
        var indent: [UInt8] = []
        while i >= 0, bytes[i] != 0x0A {
            guard bytes[i] == 0x20 || bytes[i] == 0x09 else { return nil }
            indent.insert(bytes[i], at: 0)
            i -= 1
        }
        return String(decoding: indent, as: UTF8.self)
    }

    private func parse() throws -> Node {
        var p = Parser(bytes)
        return try p.document()
    }

    private func node(at path: [String]) throws -> Node? {
        var n = try parse()
        for key in path {
            guard n.kind == .object, let m = n.members.last(where: { $0.key == key }) else { return nil }
            n = m.value
        }
        return n
    }

    final class Node {
        enum Kind { case object, array, string, number, bool, null }
        let kind: Kind
        var start = 0
        var end = 0
        var members: [Member] = []
        var items: [Node] = []
        var scalar: Any = NSNull()
        init(_ kind: Kind) { self.kind = kind }

        func foundation() -> Any {
            switch kind {
            case .object:
                var d: [String: Any] = [:]
                for m in members { d[m.key] = m.value.foundation() }
                return d
            case .array: return items.map { $0.foundation() }
            default: return scalar
            }
        }
    }

    struct Member {
        let key: String
        let keyStart: Int
        let value: Node
    }

    struct Parser {
        let b: [UInt8]
        var i = 0
        init(_ b: [UInt8]) { self.b = b }

        func fail(_ what: String) -> ManagerError {
            var line = 1
            for k in 0..<min(i, b.count) where b[k] == 0x0A { line += 1 }
            return ManagerError("Invalid JSON near line \(line): \(what)")
        }

        mutating func document() throws -> Node {
            if b.starts(with: [0xEF, 0xBB, 0xBF]) { i = 3 }   // BOM
            let n = try value()
            try skip()
            guard i == b.count else { throw fail("extra text after the end") }
            return n
        }

        mutating func skip() throws {
            while i < b.count {
                switch b[i] {
                case 0x20, 0x09, 0x0A, 0x0D: i += 1
                case UInt8(ascii: "/") where i + 1 < b.count && b[i + 1] == UInt8(ascii: "/"):
                    while i < b.count && b[i] != 0x0A { i += 1 }
                case UInt8(ascii: "/") where i + 1 < b.count && b[i + 1] == UInt8(ascii: "*"):
                    i += 2
                    while i + 1 < b.count && !(b[i] == UInt8(ascii: "*") && b[i + 1] == UInt8(ascii: "/")) { i += 1 }
                    guard i + 1 < b.count else { throw fail("unclosed comment") }
                    i += 2
                default: return
                }
            }
        }

        mutating func expect(_ c: Character) throws {
            try skip()
            guard i < b.count, b[i] == c.asciiValue! else { throw fail("expected '\(c)'") }
            i += 1
        }

        mutating func value() throws -> Node {
            try skip()
            guard i < b.count else { throw fail("unexpected end") }
            let start = i
            let n: Node
            switch b[i] {
            case UInt8(ascii: "{"):
                n = Node(.object)
                i += 1
                while true {
                    try skip()
                    guard i < b.count else { throw fail("unclosed object") }
                    if b[i] == UInt8(ascii: "}") { i += 1; break }
                    guard b[i] == UInt8(ascii: "\"") else { throw fail("expected a key") }
                    let keyStart = i
                    let key = try string()
                    try expect(":")
                    let v = try value()
                    n.members.append(Member(key: key, keyStart: keyStart, value: v))
                    try skip()
                    guard i < b.count else { throw fail("unclosed object") }
                    if b[i] == UInt8(ascii: ",") { i += 1; continue }
                    if b[i] == UInt8(ascii: "}") { i += 1; break }
                    throw fail("expected ',' or '}'")
                }
            case UInt8(ascii: "["):
                n = Node(.array)
                i += 1
                while true {
                    try skip()
                    guard i < b.count else { throw fail("unclosed array") }
                    if b[i] == UInt8(ascii: "]") { i += 1; break }
                    n.items.append(try value())
                    try skip()
                    guard i < b.count else { throw fail("unclosed array") }
                    if b[i] == UInt8(ascii: ",") { i += 1; continue }
                    if b[i] == UInt8(ascii: "]") { i += 1; break }
                    throw fail("expected ',' or ']'")
                }
            case UInt8(ascii: "\""):
                n = Node(.string)
                n.scalar = try string()
            case UInt8(ascii: "t"): n = Node(.bool); try literal("true"); n.scalar = true
            case UInt8(ascii: "f"): n = Node(.bool); try literal("false"); n.scalar = false
            case UInt8(ascii: "n"): n = Node(.null); try literal("null")
            default:
                n = Node(.number)
                while i < b.count, "+-0123456789.eE".utf8.contains(b[i]) { i += 1 }
                guard i > start, let d = Double(String(decoding: b[start..<i], as: UTF8.self)) else {
                    throw fail("unexpected character")
                }
                n.scalar = d
            }
            n.start = start
            n.end = i
            return n
        }

        mutating func literal(_ word: String) throws {
            let w = Array(word.utf8)
            guard i + w.count <= b.count, Array(b[i..<(i + w.count)]) == w else { throw fail("unexpected word") }
            i += w.count
        }

        mutating func string() throws -> String {
            i += 1   // opening quote
            var out: [UInt8] = []
            while true {
                guard i < b.count else { throw fail("unclosed string") }
                let c = b[i]
                if c == UInt8(ascii: "\"") { i += 1; break }
                if c != UInt8(ascii: "\\") { out.append(c); i += 1; continue }
                i += 1
                guard i < b.count else { throw fail("bad escape") }
                let e = b[i]
                i += 1
                switch e {
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "u"):
                    var code = try hex4()
                    if (0xD800..<0xDC00).contains(code), i + 1 < b.count,
                       b[i] == UInt8(ascii: "\\"), b[i + 1] == UInt8(ascii: "u") {
                        i += 2
                        let low = try hex4()
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    let scalar = Unicode.Scalar(code) ?? "?"
                    out.append(contentsOf: Array(String(Character(scalar)).utf8))
                default: out.append(e)   // \" \\ \/
                }
            }
            return String(decoding: out, as: UTF8.self)
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= b.count, let v = UInt32(String(decoding: b[i..<(i + 4)], as: UTF8.self), radix: 16) else {
                throw fail("bad \\u escape")
            }
            i += 4
            return v
        }
    }
}
