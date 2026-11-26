import SwiftUI
import ManagerCore

struct ItemListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let items = model.visibleItems
        let errors = errorsForSelection

        List(selection: $model.selectedItemID) {
            ForEach(errors, id: \.0) { name, message in
                Label("\(name): \(message)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            ForEach(items) { item in
                ItemRow(item: item).tag(item.id)
            }
        }
        .overlay {
            if items.isEmpty && errors.isEmpty {
                if model.tools.contains(where: \.loading) {
                    ProgressView("Reading configs…")
                } else {
                    ContentUnavailableView("Nothing here", systemImage: "tray",
                                           description: Text(model.search.isEmpty ? "No MCP servers or plugins configured." : "Nothing matches your search."))
                }
            }
        }
        .navigationTitle(title)
    }

    var title: String {
        if case .tool(let id) = model.selection { return model.toolName(id) }
        return "All tools"
    }

    var errorsForSelection: [(String, String)] {
        model.tools.compactMap { t in
            guard let e = t.error else { return nil }
            if case .tool(let id) = model.selection, id != t.id { return nil }
            return (t.provider.name, e)
        }
    }
}

struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: Item

    var body: some View {
        HStack(spacing: 10) {
            HealthDot(health: item.health, enabled: item.enabled)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).fontWeight(.medium)
                    Tag(text: item.kind.rawValue)
                    if let t = item.transport { Tag(text: t) }
                }
                HStack(spacing: 6) {
                    if model.selection == .all {
                        Image(systemName: ToolIcon.name(item.toolID)).font(.caption2)
                        Text(model.toolName(item.toolID))
                        Text("·")
                    }
                    Text(item.scope).lineLimit(1).truncationMode(.middle)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.busy.contains(item.id) {
                ProgressView().controlSize(.small)
            }
            Toggle("", isOn: Binding(
                get: { item.enabled },
                set: { on in Task { await model.setEnabled(item, on) } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!item.canToggle || model.busy.contains(item.id))
            .help(item.canToggle ? (item.enabled ? "Turn off" : "Turn on") : (item.note ?? "Can't be changed here"))
        }
        .padding(.vertical, 3)
        .opacity(item.enabled ? 1 : 0.6)
    }
}

struct Tag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct HealthDot: View {
    let health: Health
    let enabled: Bool

    var body: some View {
        Circle().fill(color).frame(width: 9, height: 9)
            .help(enabled ? health.label : "Off")
    }

    var color: Color {
        guard enabled else { return .gray.opacity(0.4) }
        switch health {
        case .connected: return .green
        case .needsAuth, .pending: return .yellow
        case .failed: return .red
        case .unknown: return .gray.opacity(0.7)
        }
    }
}
