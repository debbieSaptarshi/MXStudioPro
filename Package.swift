// swift-tools-version: 6.0
import PackageDescription

// MXStudio Pro audio engine.
//
// Module boundaries mirror the architecture: MXAudioDSP is the extension-safe
// leaf that the AUv3 target links, and nothing above it may leak into that
// target. Swift enforces the boundaries because each directory is its own
// module; the single manifest just keeps `swift build` / `swift test` to one
// command.

let swift5 = [SwiftSetting.swiftLanguageMode(.v5)]

let package = Package(
    name: "MXStudioAudio",
    // macOS 15 / iOS 18 so the render thread can use Synchronization.Atomic
    // instead of hand-rolled barriers for the playhead and transport flags.
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "MXAudioDSP", targets: ["MXAudioDSP"]),
        .library(name: "MXInstruments", targets: ["MXInstruments"]),
        .library(name: "MXAudioCore", targets: ["MXAudioCore"]),
        .library(name: "MXPacks", targets: ["MXPacks"]),
        .library(name: "MXAUv3Host", targets: ["MXAUv3Host"]),
        .library(name: "MXAudioTestHarness", targets: ["MXAudioTestHarness"]),
    ],
    dependencies: [
        .package(url: "https://github.com/AudioKit/AudioKit.git", from: "5.7.0"),
        .package(url: "https://github.com/AudioKit/SoundpipeAudioKit.git", from: "5.7.0"),
    ],
    targets: [
        // Extension-safe leaf. No AudioKit, no UI, no app-target types.
        .target(
            name: "MXAudioDSP",
            path: "Packages/MXAudioDSP/Sources",
            swiftSettings: swift5
        ),
        .target(
            name: "MXInstruments",
            dependencies: [
                "MXAudioDSP",
                .product(name: "AudioKit", package: "AudioKit"),
                .product(name: "SoundpipeAudioKit", package: "SoundpipeAudioKit"),
            ],
            path: "Packages/MXInstruments/Sources",
            swiftSettings: swift5
        ),
        .target(
            name: "MXAudioCore",
            dependencies: ["MXAudioDSP", "MXInstruments"],
            path: "Packages/MXAudioCore/Sources",
            swiftSettings: swift5
        ),
        .target(
            name: "MXPacks",
            dependencies: ["MXAudioDSP", "MXInstruments"],
            path: "Packages/MXPacks/Sources",
            swiftSettings: swift5
        ),
        .target(
            name: "MXAUv3Host",
            dependencies: ["MXAudioDSP"],
            path: "Packages/MXAUv3Host/Sources",
            swiftSettings: swift5
        ),
        .target(
            name: "MXAudioTestHarness",
            dependencies: ["MXAudioCore", "MXInstruments", "MXPacks"],
            path: "Packages/MXAudioTestHarness/Sources",
            swiftSettings: swift5
        ),

        .testTarget(
            name: "MXAudioCoreTests",
            dependencies: ["MXAudioCore", "MXAudioTestHarness"],
            path: "Tests/MXAudioCoreTests",
            swiftSettings: swift5
        ),
        .testTarget(
            name: "MXInstrumentsTests",
            dependencies: ["MXInstruments", "MXAudioTestHarness"],
            path: "Tests/MXInstrumentsTests",
            swiftSettings: swift5
        ),
        .testTarget(
            name: "MXPacksTests",
            dependencies: ["MXPacks", "MXAudioTestHarness"],
            path: "Tests/MXPacksTests",
            swiftSettings: swift5
        ),
        .testTarget(
            name: "MXAUv3HostTests",
            dependencies: ["MXAUv3Host", "MXAudioTestHarness"],
            path: "Tests/MXAUv3HostTests",
            swiftSettings: swift5
        ),
        .testTarget(
            name: "MXDeviceTests",
            dependencies: ["MXAudioCore", "MXInstruments", "MXAudioTestHarness"],
            path: "Tests/MXDeviceTests",
            swiftSettings: swift5
        ),
    ]
)
