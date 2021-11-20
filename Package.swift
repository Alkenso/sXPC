// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "sXPC",
    platforms: [
        .macOS(.v10_11),
    ],
    products: [
        .library(name: "sXPC", targets: ["sXPC"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alkenso/SwiftConvenience.git", from: "0.0.3"),
    ],
    targets: [
        .target(name: "sXPC", dependencies: ["SwiftConvenience"]),
    ]
)
