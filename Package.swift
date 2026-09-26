// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SpaceTab",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Automatic updates from GitHub Releases.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "SpaceTab",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/SpaceTab",
            linkerSettings: [
                // The app bundle carries Sparkle.framework in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "SpaceTabTests",
            dependencies: ["SpaceTab"],
            path: "Tests/SpaceTabTests"
        ),
    ]
)
