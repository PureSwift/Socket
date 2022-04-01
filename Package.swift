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
        .package(url: "git@github.com:PureSwift/swift-system.git", .branch("master")),
    ],
    targets: [
        .target(
            name: "Socket",
            dependencies: [
                .product(name: "SystemPackage", package: "swift-system")
            ]
        ),
        .testTarget(
            name: "SocketTests",
            dependencies: ["Socket"]
        )
    ]
)
