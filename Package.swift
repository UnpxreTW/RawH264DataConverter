// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "H264Decoder",
    platforms: [.iOS(.v11), .macOS(.v10_13), .tvOS(.v11)],
    products: [
        .library(name: "H264Decoder", targets: ["H264Decoder"])
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
            path: "Sources"
        )
    ]
)
