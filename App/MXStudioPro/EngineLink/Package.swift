// swift-tools-version: 6.0
import PackageDescription

/// Thin local package so the iOS app can depend on MXAudioCore without Xcode
/// crashing on the multi-product root package graph.
let package = Package(
    name: "MXStudioEngineLink",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "MXStudioEngine", targets: ["MXStudioEngine"]),
    ],
    dependencies: [
        .package(path: "../../.."),
    ],
    targets: [
        .target(
            name: "MXStudioEngine",
            dependencies: [
                .product(name: "MXAudioCore", package: "Music App"),
                .product(name: "MXAudioDSP", package: "Music App"),
                .product(name: "MXInstruments", package: "Music App"),
                .product(name: "MXPacks", package: "Music App"),
            ],
            path: "Sources"
        ),
    ]
)
