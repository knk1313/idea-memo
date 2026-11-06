// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IdeaMemo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "IdeaMemo", path: "Sources/IdeaMemo")
    ]
)
