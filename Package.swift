// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "LaunchTaskKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "LaunchTaskKit",
            targets: ["LaunchTaskKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0"),
    ],
    targets: [
        .macro(
            name: "LaunchTaskKitMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "LaunchTaskKit",
            dependencies: ["LaunchTaskKitMacros"]
        ),
        .testTarget(
            name: "LaunchTaskKitTests",
            dependencies: ["LaunchTaskKit"]
        ),
        .testTarget(
            name: "LaunchTaskKitMacrosTests",
            dependencies: [
                "LaunchTaskKitMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
