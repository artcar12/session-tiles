// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SessionTiles",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "InstanceRouter", path: "Sources/InstanceRouter"),
        .executableTarget(name: "SessionTiles", dependencies: ["InstanceRouter"], path: "Sources/SessionTiles"),
        // Built as ClaudeOpen; build.sh embeds it as Session Tiles.app/Contents/MacOS/claude-open.
        // The embedded Info.plist carries NSAppleEventsUsageDescription for when it runs on its own.
        .executableTarget(name: "ClaudeOpen", dependencies: ["InstanceRouter"], path: "Sources/ClaudeOpen",
                          exclude: ["Info.plist"],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                                                         "-Xlinker", "__info_plist",
                                                         "-Xlinker", "Sources/ClaudeOpen/Info.plist"])]),
    ]
)
