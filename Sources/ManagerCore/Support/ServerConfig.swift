import Foundation

/// Every tool writes a server a little differently. This reads the common shapes:
///   { "command": "npx", "args": [...], "env": {...} }                 Claude, Cursor, Windsurf, Gemini...
///   { "type": "http", "url": "...", "headers": {...} }                 most tools
///   { "serverUrl": "..." } / { "httpUrl": "..." }                      Windsurf / Gemini
///   { "type": "local", "command": ["npx", "x"], "environment": {...} } OpenCode
///   { "command": { "path": "...", "args": [...] } }                    older Zed
public enum ServerConfig {
    public static func fill(_ item: inout Item, from any: Any?) {
        guard let d = any as? [String: Any] else { return }
        var command: String?
        var args = d["args"] as? [String] ?? []

        if let c = d["command"] as? String {
            command = c
        } else if let arr = d["command"] as? [String], let first = arr.first {
            command = first
            args = Array(arr.dropFirst()) + args
        } else if let obj = d["command"] as? [String: Any] {
            command = obj["path"] as? String
            args = obj["args"] as? [String] ?? args
        }

        let url = (d["url"] ?? d["serverUrl"] ?? d["httpUrl"]) as? String
        if let url {
            item.target = Redact.url(url)
            let t = (d["type"] as? String)?.lowercased()
            item.transport = (t == nil || t == "remote" || t == "streamable-http" || t == "streamablehttp") ? "http" : t
        } else if let command {
            item.target = Redact.commandLine(command, args)
            item.transport = "stdio"
        }

        let env = (d["env"] ?? d["environment"]) as? [String: Any]
        item.envKeys = env.map { $0.keys.sorted() } ?? []
        item.headerKeys = (d["headers"] as? [String: Any]).map { $0.keys.sorted() } ?? []
    }
}
