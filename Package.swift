// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SleepTimerBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SleepTimerCore", targets: ["SleepTimerCore"]),
        .executable(name: "SleepTimerBar", targets: ["SleepTimerBar"])
    ],
    targets: [
        .target(
            name: "SleepTimerCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .executableTarget(
            name: "SleepTimerBar",
            dependencies: ["SleepTimerCore"]
        ),
        .testTarget(
            name: "SleepTimerCoreTests",
            dependencies: ["SleepTimerCore"]
        )
    ]
)
