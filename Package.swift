// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "H264Decoder",
    platforms: [.iOS(.v11), .macOS(.v10_13), .tvOS(.v11)],
    products: [
        .library(name: "H264Decoder", targets: ["H264Decoder"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "H264Decoder", dependencies: []),
    ]
)
