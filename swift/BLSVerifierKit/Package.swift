// swift-tools-version:6.0
import PackageDescription

// Local package vendoring supranational/blst (the audited BLS12-381 library) so dBrowser can do
// real Ethereum-style BLS verification (sync committee) locally instead of trusting a remote
// service. The C target compiles blst's amalgamated, portable (no-assembly) `server.c`.
let package = Package(
    name: "BLSVerifierKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "BLSVerifierKit", targets: ["BLSVerifierKit"])
    ],
    targets: [
        .target(
            name: "CBlst",
            path: "Sources/CBlst",
            sources: ["shim.c"],
            publicHeadersPath: "include",
            cSettings: [
                // Pure-C build: no assembly sources are compiled. __BLST_NO_ASM__ pulls in blst's
                // reference C field arithmetic (no_asm.h); __BLST_PORTABLE__ selects portable C
                // SHA-256 instead of the ARMv8/SHA-extension assembly block.
                .define("__BLST_NO_ASM__"),
                .define("__BLST_PORTABLE__"),
                .headerSearchPath("../../Vendor/blst/bindings"),
                .headerSearchPath("../../Vendor/blst/src")
            ]
        ),
        .target(
            name: "BLSVerifierKit",
            dependencies: ["CBlst"]
        ),
        .testTarget(
            name: "BLSVerifierKitTests",
            dependencies: ["BLSVerifierKit"]
        )
    ]
)
