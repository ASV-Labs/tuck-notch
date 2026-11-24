// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TuckNotch",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Automatic updates (MIT). Pinned to an exact release.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "TuckNotch",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/TuckNotch",
            linkerSettings: [
                // Sparkle.framework is bundled in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Vision"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "TuckNotchTests",
            dependencies: ["TuckNotch"],
            path: "Tests/TuckNotchTests"
        )
    ]
)
