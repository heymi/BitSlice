// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BeCut",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BeCut", targets: ["BeCut"])
    ],
    targets: [
        .executableTarget(
            name: "BeCut",
            path: "Sources/BeCut"
        ),
        .testTarget(
            name: "BeCutTests",
            dependencies: ["BeCut"],
            path: "Tests/BeCutTests",
            exclude: ["LONG_MEDIA_GATE.md"]
        )
    ]
)
