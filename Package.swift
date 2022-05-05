// swift-tools-version: 5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let libraryType: PackageDescription.Product.Library.LibraryType = .static

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
            type: libraryType,
            targets: ["Socket"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-system",
            from: "1.0.0"
        ),
    ],
    targets: [
        .target(
            name: "Socket",
            dependencies: [
                "CSocket",
                .product(name: "SystemPackage", package: "swift-system"),
            ]
        ),
        .target(
            name: "CSocket"
        ),
        .testTarget(
            name: "SocketTests",
            dependencies: ["Socket"]
        )
    ]
)
