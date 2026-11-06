// swift-tools-version: 6.2

import PackageDescription
import Foundation

let nativeLibraryPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("Native/lib").path

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.8.1"),
    ],
    targets: [
        .target(
            name: "CPaceCore",
            path: "Native",
            exclude: ["lib"],
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(["-L", nativeLibraryPath]),
                .linkedLibrary("pace_core"),
            ]
        ),
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: [
                "CPaceCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/ClaudeUsageBar",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "ClaudeUsageBarTests",
            dependencies: ["ClaudeUsageBar", "CPaceCore"],
            path: "Tests/ClaudeUsageBarTests"
        ),
    ]
)
