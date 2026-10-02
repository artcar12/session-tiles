// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SessionTiles",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SessionTiles", path: "Sources/SessionTiles")
    ]
)
