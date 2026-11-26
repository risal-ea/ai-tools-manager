import SwiftUI
import AppKit
import ManagerCore

struct DetailView: View {
    @Environment(AppModel.self) private var model
    let item: Item
    @State private var confirmRemove = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Tool", value: model.toolName(item.toolID))
                LabeledContent("Kind", value: item.kind.rawValue)
                LabeledContent("Where", value: item.scope)
                LabeledContent("Status") {
                    HStack { HealthDot(health: item.health, enabled: item.enabled); Text(item.enabled ? item.health.label : "Off") }
                }
                if let t = item.transport { LabeledContent("Transport", value: t) }
            } header: {
                Text(item.name).font(.title2).bold().textCase(nil)
            }

            if let target = item.target {
                Section(item.transport == "stdio" ? "Command" : "Address") {
                    Text(target).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
            }

            if !item.envKeys.isEmpty || !item.headerKeys.isEmpty {
                Section {
                    ForEach(item.envKeys, id: \.self) { LabeledContent($0, value: "••••") }
                    ForEach(item.headerKeys, id: \.self) { LabeledContent("Header: \($0)", value: "••••") }
                } header: {
                    Text("Environment & headers")
                } footer: {
                    Text("Values are hidden on purpose: they often hold API keys.")
                }
            }

            if let note = item.note {
                Section { Text(note).foregroundStyle(.secondary) }
            }

            Section {
                if let path = item.configPath {
                    LabeledContent("Config") {
                        Text(path).font(.caption).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }
                if let link = item.ref["link"], let url = URL(string: link) {
                    Link("Open connector settings", destination: url)
                }
                if item.canToggle {
                    Button(item.enabled ? "Turn off" : "Turn on") {
                        Task { await model.setEnabled(item, !item.enabled) }
                    }
                    .disabled(model.busy.contains(item.id))
                }
                if item.canRemove {
                    Button("Remove…", role: .destructive) { confirmRemove = true }
                        .disabled(model.busy.contains(item.id))
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Remove \(item.name) from \(model.toolName(item.toolID))?",
                            isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await model.remove(item) } }
        } message: {
            Text(item.kind == .plugin
                 ? "The plugin is uninstalled. You can install it again later."
                 : "Its entry is deleted from the config file. A backup of the file is kept next to it (.aitm-bak-…).")
        }
    }
}
