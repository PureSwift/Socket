// swift-tools-version: 6.0
import PackageDescription
import class Foundation.ProcessInfo

// force building as dynamic library
let dynamicLibrary = ProcessInfo.processInfo.environment["SWIFT_BUILD_DYNAMIC_LIBRARY"] != nil
let libraryType: PackageDescription.Product.Library.LibraryType? = dynamicLibrary ? .dynamic : nil

var package = Package(
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
            from: "1.5.0"
        ),
        .package(
            url: "https://github.com/apple/swift-log.git",
            from: "1.0.0"
        )
    ],
    targets: [
        .target(
            name: "Socket",
            dependencies: [
                "CSocket",
                .product(
                    name: "SystemPackage",
                    package: "swift-system"
                ),
            ]
        ),
        .target(
            name: "CSocket"
        ),
        .testTarget(
            name: "SocketTests",
            dependencies: [
                "Socket",
                .product(
                    name: "Logging",
                    package: "swift-log"
                )
            ]
        )
    ]
)

// SwiftPM command plugins are only supported by Swift version 5.6 and later.
#if swift(>=5.6)
let buildDocs = ProcessInfo.processInfo.environment["BUILDING_FOR_DOCUMENTATION_GENERATION"] != nil
if buildDocs {
    package.dependencies += [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    ]
}
#endif
