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
        .library(name: "sXPCStatic", type: .static, targets: ["sXPC"]),
        .library(name: "sXPCDynamic", type: .dynamic, targets: ["sXPC"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "sXPC", dependencies: []),
    ]
)
