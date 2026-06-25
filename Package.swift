// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SwiftAria",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "Aria2RPC",
            targets: ["Aria2RPC"]
        ),
        .library(
            name: "SwiftAria",
            targets: ["SwiftAria"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .target(
            name: "Aria2RPC",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .target(
            name: "SwiftAria",
            dependencies: ["Aria2RPC"],
            resources: [
                .copy("Resources/aria2c"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .testTarget(
            name: "Aria2RPCTests",
            dependencies: ["Aria2RPC"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .testTarget(
            name: "SwiftAriaTests",
            dependencies: [
                "Aria2RPC",
                "SwiftAria",
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
    ]
)
