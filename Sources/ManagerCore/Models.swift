import Foundation

public enum ItemKind: String, Sendable {
    case mcp = "MCP"
    case plugin = "Plugin"
    case `extension` = "Extension"
}

public enum Health: Hashable, Sendable {
    case unknown
    case connected
    case needsAuth
    case pending
    case failed(String)

    public var label: String {
        switch self {
        case .unknown: return "Not checked"
        case .connected: return "Connected"
        case .needsAuth: return "Needs sign-in"
        case .pending: return "Waiting for approval"
        case .failed(let why): return "Failed: \(why)"
        }
    }
}

/// One MCP server, plugin or extension of one tool.
public struct Item: Identifiable, Hashable, Sendable {
    public let id: String            // "<tool>|<kind>|<scope>|<name>": unique + stable
    public let toolID: String
    public let name: String
    public let kind: ItemKind
    public var scope: String         // "global", "project: /path", "plugin: figma", "claude.ai"
    public var transport: String?    // stdio / http / sse
    public var target: String?       // command line or URL
    public var envKeys: [String] = []      // names only, never values
    public var headerKeys: [String] = []   // names only, never values
    public var enabled: Bool = true
    public var health: Health = .unknown
    public var configPath: String?
    public var canToggle: Bool = false
    public var canRemove: Bool = false
    public var note: String?
    /// Provider-only details (project path, which list it is in, ...).
    public var ref: [String: String] = [:]

    public init(toolID: String, name: String, kind: ItemKind, scope: String) {
        self.toolID = toolID
        self.name = name
        self.kind = kind
        self.scope = scope
        self.id = "\(toolID)|\(kind.rawValue)|\(scope)|\(name)"
    }
}

public struct HealthReport: Sendable {
    public var byItemID: [String: Health] = [:]
    public var extraItems: [Item] = []   // things only the health check knows (claude.ai connectors)
    public init() {}
}

public struct ManagerError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
