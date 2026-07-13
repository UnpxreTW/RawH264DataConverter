// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RawH264DataConverter",
    platforms: [.iOS(.v14), .macOS(.v13), .tvOS(.v14)],
    products: [
        .library(name: "H264Decoder", targets: ["H264Decoder"]),
    ],
    dependencies: [
        .package(url: "https://github.com/UnpxreTW/SwiftStyleKit.git", exact: "2.1.0"),
    ],
    targets: [
        .target(
            name: "H264Decoder",
            path: "Sources",
            plugins: [
                .plugin(name: "SwiftStyleLint", package: "SwiftStyleKit"),
            ]
        ),
        .testTarget(
            name: "H264DecoderTests",
            dependencies: ["H264Decoder"],
            path: "Tests",
            plugins: [
                .plugin(name: "SwiftStyleLint", package: "SwiftStyleKit"),
            ]
        )
    ]
)
