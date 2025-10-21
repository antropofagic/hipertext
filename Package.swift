// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Hipertext",
        platforms: [.macOS(.v13)],
        dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", branch: "main"),
        .package(url: "https://github.com/thigcampos/syntax.git", branch: "main"),
        .package(url: "https://github.com/thigcampos/thread.git", branch: "main"),
        .package(url: "https://github.com/groue/GRMustache.swift", from: "7.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "hx",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Mustache", package: "GRMustache.swift"),
                .product(name: "Syntax", package: "syntax"),
                .product(name: "Thread", package: "thread")
            ]
        )
    ]
)
