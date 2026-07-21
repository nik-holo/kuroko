// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "kuroko",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "kuroko",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/kuroko",
            linkerSettings: [
                // Sparkle.framework is copied into Contents/Frameworks by make-app.sh
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
