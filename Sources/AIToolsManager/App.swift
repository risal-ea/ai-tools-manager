import SwiftUI
import AppKit
import ManagerCore

@main
struct AIToolsManagerApp: App {
    static let mainWindowID = "main"
    @State private var model = AppModel()

    init() {
        // Started with `swift run` there is no .app bundle: make it a normal app with a Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        // One main window (not a group), so the menu bar's "Open…" brings back the same window.
        Window("AI Tools Manager", id: Self.mainWindowID) {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 560)
                .task { await model.loadOnce() }
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") { Task { await model.refreshAll() } }
                    .keyboardShortcut("r")
            }
        }

        // The icon in the top menu bar. It stays there after the window is closed.
        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } content: {
            Group {
                if model.selection == .links {
                    LinksView()
                } else {
                    ItemListView()
                }
            }
            .navigationSplitViewColumnWidth(min: 420, ideal: 520)
        } detail: {
            if let item = model.selectedItem {
                DetailView(item: item)
            } else {
                ContentUnavailableView("Pick an item", systemImage: "puzzlepiece.extension",
                                       description: Text("Choose an MCP server or plugin to see its details."))
            }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search name, tool, command")
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $model.showPlugins) { Label("Show plugins", systemImage: "puzzlepiece") }
                    .help("Show plugins and extensions too, not only MCP servers")
                Button { Task { await model.refreshAll() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Read every tool's config again and re-check health (⌘R)")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let banner = model.banner {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(banner)
                    Spacer()
                    Button("Dismiss") { model.banner = nil }.buttonStyle(.borderless)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.yellow.opacity(0.18))
            }
        }
        .alert("Couldn't do that", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }
}
