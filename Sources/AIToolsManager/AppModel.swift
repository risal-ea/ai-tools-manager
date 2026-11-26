import Foundation
import Observation
import ManagerCore

enum SidebarSelection: Hashable {
    case all
    case tool(String)
    case links
}

struct ToolState: Identifiable {
    let provider: ToolProvider
    var items: [Item] = []
    var error: String?
    var loading = false
    var checkingHealth = false
    var id: String { provider.id }
}

/// Holds what the window shows. All work goes through the providers.
@MainActor
@Observable
final class AppModel {
    var tools: [ToolState] = []
    var selection: SidebarSelection? = .all
    var selectedItemID: Item.ID?
    var search = ""
    var showPlugins = true
    /// "Restart Cursor to apply" etc.
    var banner: String?
    var lastError: String?
    var busy: Set<Item.ID> = []

    let env = ToolEnv.live()

    private var loaded = false

    init() {
        tools = Registry.providers(env: env).filter { $0.isInstalled() }.map { ToolState(provider: $0) }
        // Load at launch, so the menu bar icon can show failures before any window is opened.
        Task { await self.loadOnce() }
    }

    /// The first load; the window and the menu bar both ask for it, only the first call runs.
    func loadOnce() async {
        guard !loaded else { return }
        loaded = true
        await refreshAll()
    }

    var allItems: [Item] { tools.flatMap(\.items) }

    var isRefreshing: Bool { tools.contains { $0.loading || $0.checkingHealth } }

    /// MCP servers that are on but failed their health check (shown on the menu bar icon).
    var failedCount: Int {
        allItems.filter { item in
            guard item.enabled, item.kind == .mcp, case .failed = item.health else { return false }
            return true
        }.count
    }

    var visibleItems: [Item] {
        var list: [Item]
        switch selection {
        case .tool(let id): list = tools.first { $0.id == id }?.items ?? []
        case .links, .none: list = []
        case .all: list = allItems
        }
        if !showPlugins { list = list.filter { $0.kind == .mcp } }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q) || $0.scope.lowercased().contains(q)
                    || ($0.target?.lowercased().contains(q) ?? false) || toolName($0.toolID).lowercased().contains(q)
            }
        }
        return list
    }

    var selectedItem: Item? { allItems.first { $0.id == selectedItemID } }

    func toolName(_ id: String) -> String { tools.first { $0.id == id }?.provider.name ?? id }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for t in tools { group.addTask { await self.refresh(t.id) } }
        }
    }

    func refresh(_ toolID: String, health: Bool = true) async {
        guard let i = tools.firstIndex(where: { $0.id == toolID }) else { return }
        let provider = tools[i].provider
        tools[i].loading = true
        do {
            let items = try await provider.load()
            update(toolID) { $0.items = items; $0.error = nil; $0.loading = false }
        } catch {
            update(toolID) { $0.error = error.localizedDescription; $0.loading = false }
            return
        }
        if health { await checkHealth(toolID) }
    }

    /// Slow: starts each server. Runs after the list is shown.
    func checkHealth(_ toolID: String) async {
        guard let t = tools.first(where: { $0.id == toolID }) else { return }
        update(toolID) { $0.checkingHealth = true }
        let report = await t.provider.health(for: t.items)
        update(toolID) { state in
            state.checkingHealth = false
            for k in state.items.indices {
                if let h = report.byItemID[state.items[k].id] { state.items[k].health = h }
            }
            let known = Set(state.items.map(\.id))
            state.items += report.extraItems.filter { !known.contains($0.id) }
        }
    }

    func setEnabled(_ item: Item, _ on: Bool) async {
        await perform(item) { try await $0.setEnabled(item, on) }
    }

    func remove(_ item: Item) async {
        await perform(item) { try await $0.remove(item) }
        if selectedItemID == item.id { selectedItemID = nil }
    }

    private func perform(_ item: Item, _ work: (ToolProvider) async throws -> Void) async {
        guard let provider = tools.first(where: { $0.id == item.toolID })?.provider else { return }
        busy.insert(item.id)
        defer { busy.remove(item.id) }
        do {
            try await work(provider)
            if provider.needsRestart { banner = "Restart \(provider.name) for this change to take effect." }
        } catch {
            lastError = error.localizedDescription
        }
        await refresh(item.toolID, health: false)
    }

    private func update(_ toolID: String, _ change: (inout ToolState) -> Void) {
        guard let i = tools.firstIndex(where: { $0.id == toolID }) else { return }
        change(&tools[i])
    }
}
