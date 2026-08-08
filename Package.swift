// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Notchshell",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0"),
        // Pinned exactly, not `from:`. This dependency is pre-1.0, so `from: "0.7.1"`
        // let SPM resolve 0.11.0, which does not compile against the current
        // toolchain — `sending 'sendContinuationResumed' risks causing data races`.
        // That went unnoticed for a long time because .build held objects from an
        // older toolchain; the failure only appeared once the cache was invalidated.
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .binaryTarget(
            name: "GhosttyKit",
            path: "vendor/ghostty/macos/GhosttyKit.xcframework"
        ),
        .executableTarget(
            name: "Notchshell",
            dependencies: [
                "KeyboardShortcuts",
                "GhosttyKit",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Notchshell/Sources/Notchshell",
            // The Finder extension is compiled by `build-install.sh` into an `.appex`,
            // not by SPM — which cannot produce one. Excluded so its source is not
            // copied into the app as a resource.
            exclude: ["../../Resources/finder-extension"],
            resources: [
                .process("../../Resources"),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreText"),
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "NotchshellTests",
            dependencies: ["Notchshell"],
            path: "Notchshell/Tests/NotchshellTests"
        ),
    ]
)
