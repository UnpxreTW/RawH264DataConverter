//
//  Project.swift
//  UnpxreTW/SwiftH264Decoder
//
//  Copyright © 2024 Skywind. All rights reserved.
//

import ProjectDescription

let project = Project(
	name: "SwiftH264Decoder",
	targets: [
		.target(
			name: "SwiftH264Decoder",
			destinations: .iOS,
			product: .framework,
			bundleId: "",
			infoPlist: nil,
			sources: ["Sources/**/*"],
			dependencies: []
		)
	]
)
