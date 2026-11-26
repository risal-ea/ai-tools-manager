import SwiftUI
import AppKit
import ServiceManagement
import ManagerCore

/// The icon in the Mac's top menu bar. Turns into a warning (with a count) when a server fails.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let failed = model.failedCount
        if failed > 0 {
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("\(failed)")
            }
        } else {
            Image(systemName: "puzzlepiece.extension")
        }
    }
}

/// The panel that drops down from the menu bar icon: every tool's MCP servers with a quick on/off switch.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            // Grows with the content, scrolls once it's taller than 480pt.
            ViewThatFits(in: .vertical) {
                toolList
                ScrollView { toolList }
            }
            .frame(maxHeight: 480)
            messages
            Divider()
            footer
        }
        .frame(width: 340)
        .task { await model.loadOnce() }
    }

    // MARK: Parts

    var header: some View {
        HStack {
            Text("AI Tools").font(.headline)
            Spacer()
            if model.isRefreshing { ProgressView().controlSize(.small) }
            Button { Task { await model.refreshAll() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Read every tool's config again and re-check health")
                .disabled(model.isRefreshing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    var toolList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.tools) { tool in
                ToolSection(tool: tool, open: show)
            }
            if model.tools.isEmpty {
                Text("No AI tools found on this Mac.").foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder var messages: some View {
        if let banner = model.banner {
            Note(text: banner, icon: "arrow.triangle.2.circlepath", tint: .yellow) { model.banner = nil }
        }
        if let error = model.lastError {
            Note(text: error, icon: "exclamationmark.triangle", tint: .red) { model.lastError = nil }
        }
    }

    var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuButton(title: "Open AI Tools Manager…", icon: "macwindow") { show(nil) }
            // Only an installed .app can start at login (not `swift run`).
            if Bundle.main.bundleURL.pathExtension == "app" {
                Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
                    .toggleStyle(.checkbox)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
            MenuButton(title: "Quit", icon: "power") { NSApp.terminate(nil) }
        }
        .padding(6)
    }

    // MARK: Actions

    /// Brings up the main window, with `item` selected if given.
    func show(_ item: Item?) {
        if let item {
            model.selection = .tool(item.toolID)
            model.selectedItemID = item.id
        }
        openWindow(id: AIToolsManagerApp.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            model.lastError = "Couldn't change “Open at login”: \(error.localizedDescription)"
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// One tool: its local MCP servers, plus a one-line summary of its claude.ai connectors.
private struct ToolSection: View {
    @Environment(AppModel.self) private var model
    let tool: ToolState
    let open: (Item?) -> Void

    var body: some View {
        let servers = tool.items.filter { $0.kind == .mcp && $0.scope != "claude.ai" }
        let connectors = tool.items.filter { $0.scope == "claude.ai" }

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: ToolIcon.name(tool.id)).frame(width: 16)
                Text(tool.provider.name).fontWeight(.semibold)
                if tool.loading || tool.checkingHealth { ProgressView().controlSize(.mini) }
                Spacer()
            }
            .font(.callout)

            if let error = tool.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).lineLimit(2)
            } else if servers.isEmpty && connectors.isEmpty && !tool.loading {
                Text("No MCP servers").font(.caption).foregroundStyle(.secondary).padding(.leading, 22)
            }

            ForEach(servers) { item in
                ServerRow(item: item, open: open)
            }

            if !connectors.isEmpty {
                ConnectorSummary(connectors: connectors)
            }
        }
    }
}

private struct ServerRow: View {
    @Environment(AppModel.self) private var model
    let item: Item
    let open: (Item?) -> Void

    var body: some View {
        let busy = model.busy.contains(item.id)
        HStack(spacing: 8) {
            HealthDot(health: item.health, enabled: item.enabled)
            Button { open(item) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    if item.scope != "global" {
                        Text(item.scope).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show details in the main window")
            if busy { ProgressView().controlSize(.mini) }
            Toggle("", isOn: Binding(
                get: { item.enabled },
                set: { on in Task { await model.setEnabled(item, on) } }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .disabled(!item.canToggle || busy)
            .help(item.canToggle ? (item.enabled ? "Turn off" : "Turn on") : (item.note ?? "Can't be changed here"))
        }
        .padding(.leading, 4)
        .opacity(item.enabled ? 1 : 0.6)
    }
}

/// "26 claude.ai connectors · 3 need sign-in", linking to where they're managed.
private struct ConnectorSummary: View {
    let connectors: [Item]

    var body: some View {
        let needSignIn = connectors.filter { $0.health == .needsAuth }.count
        let link = connectors.first?.ref["link"].flatMap(URL.init(string:))
        HStack(spacing: 8) {
            Image(systemName: "cloud").font(.caption).frame(width: 9)
            Text("\(connectors.count) claude.ai connectors" + (needSignIn > 0 ? " · \(needSignIn) need sign-in" : ""))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let link {
                Link(destination: link) { Image(systemName: "arrow.up.right.square") }
                    .help("Manage them at claude.ai → Settings → Connectors")
            }
        }
        .padding(.leading, 4)
    }
}

private struct Note: View {
    let text: String
    let icon: String
    let tint: Color
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(tint.opacity(0.15))
    }
}

/// A full-width row that highlights on hover, like a real menu item.
private struct MenuButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(hovering ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
