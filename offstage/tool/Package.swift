// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "offstage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "offstage",
            path: "Sources/offstage",
            swiftSettings: [.unsafeFlags(["-Onone"], .when(configuration: .debug))],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
