// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AppleDocsTool",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "apple-docs", targets: ["AppleDocsTool"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0")
    ],
    targets: [
        // Library target containing all the core code (testable)
        .target(
            name: "AppleDocsToolCore",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/AppleDocsTool",
            exclude: ["main.swift"]
        ),
        // Executable target with just the entry point
        .executableTarget(
            name: "AppleDocsTool",
            dependencies: ["AppleDocsToolCore"],
            path: "Sources/AppleDocsToolMain"
        ),
        // Test target
        .testTarget(
            name: "AppleDocsToolTests",
            dependencies: ["AppleDocsToolCore"]
        )
    ]
)
