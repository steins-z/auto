// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnapClip",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SnapClip",
            path: "Sources/SnapClip",
            exclude: ["SnapClip-Info.plist"],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
