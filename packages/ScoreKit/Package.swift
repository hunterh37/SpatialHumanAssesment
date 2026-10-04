// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ScoreKit",
    platforms: [.macOS(.v14), .visionOS(.v2)],
    products: [
        .library(name: "ScoreKit", targets: ["ScoreKit"]),
        .executable(name: "scorekit", targets: ["ScoreKitCLI"]),
    ],
    targets: [
        // Session model, signal processing, per-game metrics, norms, Spatial Age. No UI, no ARKit.
        .target(name: "ScoreKit"),
        // Synthetic telemetry generator. Tooling only, never linked into the app.
        .target(name: "ScoreKitSynth", dependencies: ["ScoreKit"]),
        .executableTarget(name: "ScoreKitCLI", dependencies: ["ScoreKit", "ScoreKitSynth"]),
        .testTarget(name: "ScoreKitTests", dependencies: ["ScoreKit", "ScoreKitSynth"]),
    ],
    swiftLanguageModes: [.v5]
)
