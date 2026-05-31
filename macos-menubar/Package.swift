// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Speakeasy",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "Speakeasy",
            dependencies: [],
            resources: [
                // Asset catalog, not sure this is being processed correctly
                .process("Resources/Assets.xcassets"),
                // This seems to be processed correctly (old icon style)
                .copy("Resources/AppIcon.icns"),
            ],
            cSettings: [
                .headerSearchPath("../core")
            ],
            linkerSettings: [
                .unsafeFlags(
                    [
                        "../core/target/release/libspeakeasy_core.a"
                    ], .when(platforms: [.macOS])),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("MetalPerformanceShaders"),
                .linkedLibrary("c++"),
            ]
        )
        // .testTarget(
        //     name: "SpeakeasyTests",
        //     dependencies: ["Speakeasy"]),
    ]
)
