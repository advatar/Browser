// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftLM",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "Contracts", targets: ["Contracts"]),
        .library(name: "LoggingKit", targets: ["LoggingKit"]),
        .library(name: "MemoryEstimator", targets: ["MemoryEstimator"]),
        .library(name: "BenchmarkKit", targets: ["BenchmarkKit"]),
        .library(name: "ModelInspection", targets: ["ModelInspection"]),
        .library(name: "Storage", targets: ["Storage"]),
        .library(name: "RuntimeAdapters", targets: ["RuntimeAdapters"]),
        .library(name: "ControlPlane", targets: ["ControlPlane"]),
        .library(name: "SwiftLMUI", targets: ["SwiftLMUI"]),
        .executable(name: "swiflm-control-plane", targets: ["SwiftLMControlPlane"]),
    ],
    targets: [
        .target(
            name: "Contracts"
        ),
        .target(
            name: "LoggingKit",
            dependencies: ["Contracts"]
        ),
        .target(
            name: "MemoryEstimator",
            dependencies: ["Contracts"]
        ),
        .target(
            name: "BenchmarkKit",
            dependencies: ["Contracts", "MemoryEstimator"]
        ),
        .target(
            name: "ModelInspection",
            dependencies: ["Contracts"]
        ),
        .target(
            name: "Storage",
            dependencies: ["Contracts", "LoggingKit"],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "RuntimeAdapters",
            dependencies: ["Contracts", "MemoryEstimator"]
        ),
        .target(
            name: "ControlPlane",
            dependencies: [
                "BenchmarkKit",
                "Contracts",
                "LoggingKit",
                "MemoryEstimator",
                "ModelInspection",
                "RuntimeAdapters",
                "Storage"
            ]
        ),
        .target(
            name: "SwiftLMUI",
            dependencies: ["ControlPlane", "Contracts"]
        ),
        .executableTarget(
            name: "SwiftLMControlPlane",
            dependencies: ["ControlPlane"]
        ),
        .testTarget(
            name: "ControlPlaneTests",
            dependencies: ["ControlPlane", "Contracts", "RuntimeAdapters"]
        ),
        .testTarget(
            name: "MemoryEstimatorTests",
            dependencies: ["MemoryEstimator", "Contracts"]
        ),
        .testTarget(
            name: "StorageTests",
            dependencies: ["Storage"]
        ),
        .testTarget(
            name: "SwiftLMUITests",
            dependencies: ["SwiftLMUI"]
        )
    ]
)
