// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "macegg",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "macegg", path: "Sources/macegg")
    ]
)
