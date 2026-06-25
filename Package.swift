// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SwiftAria",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "SwiftAria",
            targets: ["SwiftAria"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftAria",
            dependencies: ["CAria2Bridge"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .target(
            name: "CAria2Bridge",
            dependencies: ["Aria2Binary"],
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
            ]
        ),
        .binaryTarget(
            name: "Aria2Binary",
            path: "Vendor/Aria2.xcframework"
        ),
        .testTarget(
            name: "SwiftAriaTests",
            dependencies: ["SwiftAria"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
    ]
)
