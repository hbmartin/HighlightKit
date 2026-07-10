// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "HighlightKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "HighlightKit", targets: ["HighlightKit"]),
    ],
    targets: [
        .target(
            name: "HighlightKit",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "HighlightKitTests",
            dependencies: ["HighlightKit"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .executableTarget(
            name: "highlight-bench",
            dependencies: ["HighlightKit"],
            path: "Benchmarks/highlight-bench"
        ),
    ]
)
