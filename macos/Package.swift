// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.8.1"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/ClaudeUsageBar",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "ClaudeUsageBarTests",
            dependencies: ["ClaudeUsageBar"],
            path: "Tests/ClaudeUsageBarTests"
        ),
    ]
)
