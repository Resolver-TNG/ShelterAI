// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnpiApp",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "AnpiApp", targets: ["AnpiApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/john-rocky/CoreML-LLM", branch: "main")
    ],
    targets: [
        .target(
            name: "AnpiApp",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "CoreMLLLM", package: "CoreML-LLM"),
            ],
            path: "Sources/AnpiApp",
            resources: [.copy("../../Resources")]
        )
    ]
)
