// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BrowserAutomationKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "BrowserAutomationKit",
            targets: ["BrowserAutomationKit"]
        ),
        .executable(
            name: "browser-automation-kit",
            targets: ["browser-automation-kit"]
        )
    ],
    targets: [
        .target(name: "BrowserAutomationKit"),
        .executableTarget(
            name: "browser-automation-kit",
            dependencies: ["BrowserAutomationKit"]
        ),
        .testTarget(
            name: "BrowserAutomationKitTests",
            dependencies: ["BrowserAutomationKit"]
        )
    ]
)
