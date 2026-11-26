// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AIToolsManager",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Only for reading Continue's config.yaml.
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        // Everything that reads/changes the tools' config: no UI, fully testable.
        .target(name: "ManagerCore", dependencies: ["Yams"]),
        // The SwiftUI window.
        .executableTarget(name: "AIToolsManager", dependencies: ["ManagerCore"]),
        // `swift run aitm`: the same lists in the terminal (read-only).
        .executableTarget(name: "aitm", dependencies: ["ManagerCore"]),
        .testTarget(name: "ManagerCoreTests", dependencies: ["ManagerCore"]),
    ]
)
