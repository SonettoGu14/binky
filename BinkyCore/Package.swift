// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BinkyCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "BinkyCoreShared", targets: ["BinkyCoreShared"]),
        .library(name: "BinkyCoreSort", targets: ["BinkyCoreSort"]),
        .library(name: "BinkyCLILib", targets: ["BinkyCLILib"]),
        .executable(name: "binky", targets: ["BinkyCLI"]),
    ],
    targets: [
        .target(
            name: "BinkyCoreShared",
            dependencies: [],
            path: "Sources/BinkyCoreShared"
        ),
        .target(
            name: "BinkyCoreSort",
            dependencies: ["BinkyCoreShared"],
            path: "Sources/BinkyCoreSort"
        ),
        .target(
            name: "BinkyCLILib",
            dependencies: ["BinkyCoreShared", "BinkyCoreSort"],
            path: "Sources/BinkyCLILib"
        ),
        .executableTarget(
            name: "BinkyCLI",
            dependencies: ["BinkyCLILib"],
            path: "Sources/BinkyCLI"
        ),
    ]
)
