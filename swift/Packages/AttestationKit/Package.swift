// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AttestationKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "AttestationKit",
            targets: ["AttestationKit"]
        )
    ],
    targets: [
        .target(
            name: "AttestationKit",
            publicHeadersPath: "Include"
        ),
        .testTarget(
            name: "AttestationKitTests",
            dependencies: ["AttestationKit"]
        )
    ]
)
