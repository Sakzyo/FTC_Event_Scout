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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "FTCEventScout",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/FTCEventScout",
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("Security"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "FTCEventScoutTests",
            dependencies: ["FTCEventScout"],
            path: "tests/FTCEventScoutTests"
        ),
    ]
)
