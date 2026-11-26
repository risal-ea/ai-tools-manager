import Foundation
import ManagerCore

// The same lists as the app, in the terminal.
//   swift run aitm                     list everything (read-only)
//   swift run aitm --health            also start the servers and show their status
//   swift run aitm off <tool> <name>   turn off   (tool = claude-code, codex, cursor, ...)
//   swift run aitm on <tool> <name>    turn on
//   swift run aitm remove <tool> <name>
let env = ToolEnv.live()
let args = Array(CommandLine.arguments.dropFirst())
let providers = Registry.providers(env: env).filter { $0.isInstalled() }

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

if let verb = args.first, ["on", "off", "remove"].contains(verb) {
    guard args.count == 3 else { fail("usage: aitm \(verb) <tool> <name>") }
    guard let p = providers.first(where: { $0.id == args[1] }) else {
        fail("No installed tool '\(args[1])'. Tools: \(providers.map(\.id).joined(separator: ", "))")
    }
    let matches = try await p.load().filter { $0.name == args[2] }
    guard let item = matches.first(where: { verb == "remove" ? $0.canRemove : $0.canToggle }) ?? matches.first else {
        fail("\(p.name) has nothing called '\(args[2])'.")
    }
    if matches.count > 1 { print("note: \(matches.count) items are called '\(item.name)'; using the one in \(item.scope)") }
    guard verb == "remove" ? item.canRemove : item.canToggle else { fail(item.note ?? "\(item.name) can't be changed here.") }
    do {
        if verb == "remove" { try await p.remove(item) } else { try await p.setEnabled(item, verb == "on") }
    } catch {
        fail("error: \(error.localizedDescription)")
    }
    print("\(verb): \(p.name) · \(item.name) (\(item.scope))\(p.needsRestart ? ". Restart \(p.name) to apply." : "")")
    exit(0)
}

let withHealth = args.contains("--health")
for p in providers {
    print("\n== \(p.name)  [\(p.id)]")
    do {
        var items = try await p.load()
        if withHealth {
            let r = await p.health(for: items)
            items = items.map { var i = $0; if let h = r.byItemID[i.id] { i.health = h }; return i } + r.extraItems
        }
        if items.isEmpty { print("   (nothing configured)") }
        for i in items {
            let state = i.enabled ? "on " : "off"
            let health = i.health == .unknown ? "" : "  [\(i.health.label)]"
            print("   \(state)  \(i.kind.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(i.name)  ·  \(i.scope)\(health)")
        }
    } catch {
        print("   error: \(error.localizedDescription)")
    }
}
