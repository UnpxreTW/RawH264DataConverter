//
//  Project.swift
//  UnpxreTW/RawH264DataConverter
//
//  Copyright © 2024 UnpxreTW. All rights reserved.
//

import ProjectDescription

let target: Target = .target(
	name: "RawH264DataConverter",
	destinations: .iOS,
	product: .framework,
	bundleId: "",
	infoPlist: nil,
	sources: ["Sources/**/*"],
	dependencies: [
		.package(product: "SwiftLintBuildToolPlugin", type: .plugin)
	]
)

let developmentTools: [Package] = [
	.remote(
		url: "https://github.com/SimplyDanny/SwiftLintPlugins.git",
		requirement: .upToNextMajor(from: Version(0, 55, 0))
	),
	.remote(
		url: "https://github.com/UnpxreTW/SwiftFormat.git",
		requirement: .branch("Unpxre")
	)
]

let project = Project(
	name: "RawH264DataConverter",
	packages: developmentTools,
	targets: [
		target
	]
)
