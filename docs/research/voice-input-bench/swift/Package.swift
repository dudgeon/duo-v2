// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "asrbench",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Newest FluidAudio main at the time of writing (has Unified/Nemotron/EOU streaming and CustomVocabulary).
        .package(url: "https://github.com/FluidInference/FluidAudio.git",
                 revision: "e560c6445ffdc42e60c7b282d162aae271f18e2a", traits: []),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "asrbench",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
