// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Spike",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/AudioKit/AudioKit.git", from: "5.7.0"),
        .package(url: "https://github.com/AudioKit/SoundpipeAudioKit.git", from: "5.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "Spike",
            dependencies: [
                .product(name: "AudioKit", package: "AudioKit"),
                .product(name: "SoundpipeAudioKit", package: "SoundpipeAudioKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
