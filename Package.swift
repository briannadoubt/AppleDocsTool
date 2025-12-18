// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AppleDocsTool",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AppleDocsTool", targets: ["AppleDocsTool"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0")
    ],
    targets: [
        .executableTarget(
            name: "AppleDocsTool",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ]
        )
    ]
)
