// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "H264Decoder",
    platforms: [.iOS(.v11), .macOS(.v10_13), .tvOS(.v11)],
    products: [
        .library(
            name: "H264Decoder",
            targets: ["H264Decoder"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/nicklockwood/SwiftFormat.git",
            from: Version(0, 50, 8)
        )
    ],
    targets: [
        .target(
            name: "H264Decoder",
            plugins: [
                "SwiftLintBinary"
            ]
        ),
        .binaryTarget(
            name: "SwiftLintBinary",
            url: "https://github.com/realm/SwiftLint/releases/download/0.50.3/SwiftLintBinary-macos.artifactbundle.zip",
            checksum: "abe7c0bb505d26c232b565c3b1b4a01a8d1a38d86846e788c4d02f0b1042a904"
        )
    ]
)
