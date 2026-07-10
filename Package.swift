// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BiCut",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BiCut", targets: ["BiCut"])
    ],
    targets: [
        .executableTarget(
            name: "BiCut",
            path: "Sources/BiCut"
        )
    ]
)
