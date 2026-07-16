// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "kuroko",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "kuroko", path: "Sources/kuroko")
    ]
)
