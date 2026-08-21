// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "FTCEventScout",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "FTCEventScout", targets: ["FTCEventScout"]),
    ],
    targets: [
        .executableTarget(
            name: "FTCEventScout",
            path: "Sources/FTCEventScout",
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "FTCEventScoutTests",
            dependencies: ["FTCEventScout"],
            path: "tests/FTCEventScoutTests"
        ),
    ]
)
