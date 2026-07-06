// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GMK67Driver",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "gmk67", targets: ["GMK67Driver"]),
        .executable(name: "GMK67App", targets: ["GMK67App"])
    ],
    targets: [
        .target(
            name: "GMK67Core",
            path: "Sources/GMK67Core"
        ),
        .executableTarget(
            name: "GMK67Driver",
            dependencies: ["GMK67Core"],
            path: "Sources/GMK67Driver"
        ),
        .executableTarget(
            name: "GMK67App",
            dependencies: ["GMK67Core"],
            path: "Sources/GMK67App"
        )
    ]
)
