// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RawH264DataConverter",
    platforms: [.iOS(.v9), .macOS(.v10_11), .tvOS(.v11)],
    products: [
        .library(name: "H264Decoder", targets: ["H264Decoder"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "H264Decoder",
            path: "Sources"
        )
    ]
)
