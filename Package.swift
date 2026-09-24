// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SpaceTab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SpaceTab",
            path: "Sources/SpaceTab"
        ),
        .testTarget(
            name: "SpaceTabTests",
            dependencies: ["SpaceTab"],
            path: "Tests/SpaceTabTests"
        ),
    ]
)
