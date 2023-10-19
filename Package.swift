// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "sXPC",
    platforms: [
        .macOS(.v10_13),
    ],
    products: [
        .library(name: "sXPC", targets: ["sXPC"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alkenso/SwiftSpellbook.git", exact: "0.3.0"),
    ],
    targets: [
        .target(
            name: "sXPC",
            dependencies: [.product(name: "SpellbookFoundation", package: "SwiftSpellbook")]
        ),
        .testTarget(
            name: "sXPCTests",
            dependencies: [
                "sXPC",
                .product(name: "SpellbookFoundation", package: "SwiftSpellbook"),
                .product(name: "SpellbookTestUtils", package: "SwiftSpellbook"),
            ]
        ),
    ]
)
