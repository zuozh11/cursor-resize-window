// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "cursor-resize-window",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "cursor-resize-window", targets: ["CursorResizeWindowCLI"])
    ],
    targets: [
        .target(name: "CursorResizeWindowCore"),
        .executableTarget(
            name: "CursorResizeWindowCLI",
            dependencies: ["CursorResizeWindowCore"]
        ),
        .testTarget(
            name: "CursorResizeWindowCoreTests",
            dependencies: ["CursorResizeWindowCore"]
        )
    ]
)
