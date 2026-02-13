// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PermitModel",
    platforms: [
        .iOS(.v17),
        .macOS(.v12),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "PermitModel",
            targets: ["PermitModel"]
        ),
    ],
    targets: [
        .target(
            name: "PermitModel"
        ),
        .testTarget(
            name: "PermitModelTests",
            dependencies: ["PermitModel"]
        ),
    ]
)
