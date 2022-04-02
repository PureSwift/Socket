// swift-tools-version: 5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Socket",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library(
            name: "Socket",
            targets: ["Socket"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/PureSwift/swift-system.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.0.2"),
    ],
    targets: [
        .target(
            name: "Socket",
            dependencies: [
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "Atomics", package: "swift-atomics"),
            ]
        ),
        .testTarget(
            name: "SocketTests",
            dependencies: ["Socket"]
        )
    ]
)
