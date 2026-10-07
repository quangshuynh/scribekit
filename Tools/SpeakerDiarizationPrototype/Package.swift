// swift-tools-version: 6.0
//
// Speaker diarization feasibility prototype for Interval 33.
//
// Developer tooling only. Nothing here is linked into ScribeKit, the package
// declares no dependencies, and every framework it uses ships with macOS.

import PackageDescription

let package = Package(
    name: "SpeakerDiarizationPrototype",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "DiarizationCore"),
        .executableTarget(name: "diarization-lab", dependencies: ["DiarizationCore"]),
        .testTarget(name: "DiarizationCoreTests", dependencies: ["DiarizationCore"]),
    ],
    swiftLanguageModes: [.v5]
)
