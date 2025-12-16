// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AFMRunner",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "AFMRunner",
            targets: ["AFMRunner"]
        )
    ],
    targets: [
        .target(
            name: "AFMRunner",
            publicHeadersPath: "Include"
        ),
        .testTarget(
            name: "AFMRunnerTests",
            dependencies: ["AFMRunner"]
        )
    ]
)
