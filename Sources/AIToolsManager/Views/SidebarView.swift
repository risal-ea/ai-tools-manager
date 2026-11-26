import SwiftUI
import ManagerCore

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Label {
                HStack { Text("All"); Spacer(); count(model.allItems.count) }
            } icon: { Image(systemName: "square.grid.2x2") }
            .tag(SidebarSelection.all)

            Section("Tools on this Mac") {
                ForEach(model.tools) { t in
                    Label {
                        HStack {
                            Text(t.provider.name)
                            Spacer()
                            if t.loading || t.checkingHealth {
                                ProgressView().controlSize(.small)
                            } else if t.error != nil {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            } else {
                                count(t.items.count)
                            }
                        }
                    } icon: { Image(systemName: ToolIcon.name(t.id)) }
                    .tag(SidebarSelection.tool(t.id))
                }
            }

            Section("In the cloud") {
                Label("Connectors", systemImage: "cloud").tag(SidebarSelection.links)
            }
        }
        .listStyle(.sidebar)
    }

    func count(_ n: Int) -> some View {
        Text("\(n)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
    }
}

enum ToolIcon {
    static func name(_ toolID: String) -> String {
        switch toolID {
        case "claude-code": return "terminal"
        case "claude-desktop": return "message"
        case "codex": return "chevron.left.forwardslash.chevron.right"
        case "cursor", "windsurf", "zed", "vscode": return "curlybraces"
        case "cline", "roo", "continue": return "puzzlepiece.extension"
        case "gemini": return "sparkles"
        case "lmstudio": return "cpu"
        case "kiro", "amazonq", "copilot-cli", "opencode": return "terminal"
        default: return "app"
        }
    }
}

struct LinksView: View {
    var body: some View {
        List {
            Section {
                ForEach(Registry.cloudLinks, id: \.url) { link in
                    Link(destination: URL(string: link.url)!) {
                        Label(link.name, systemImage: "arrow.up.right.square")
                    }
                }
            } footer: {
                Text("These are stored in your account online, not on this Mac. Claude Code's claude.ai connectors also show in the list after the health check.")
            }
        }
    }
}
