// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyClean",
    platforms: [.macOS("14.0")],
    targets: [
        .executableTarget(
            name: "KeyClean",
            path: "Sources/KeyClean",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
