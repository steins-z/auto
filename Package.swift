// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnapClipAnnotations",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SnapClipAnnotations",
            targets: ["SnapClipAnnotations"]
        )
    ],
    targets: [
        .target(
            name: "SnapClipAnnotations",
            path: "Sources/SnapClipAnnotations"
        ),
        .testTarget(
            name: "SnapClipAnnotationsTests",
            dependencies: ["SnapClipAnnotations"],
            path: "Tests/SnapClipAnnotationsTests"
        )
    ]
)
