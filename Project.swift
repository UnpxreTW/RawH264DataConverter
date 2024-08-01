//
//  Project.swift
//  UnpxreTW/RawH264DataConverter
//
//  Copyright © 2024 Skywind. All rights reserved.
//

import ProjectDescription

let project = Project(
	name: "RawH264DataConverter",
	targets: [
		.target(
			name: "RawH264DataConverter",
			destinations: .iOS,
			product: .framework,
			bundleId: "",
			infoPlist: nil,
			sources: ["Sources/**/*"],
			dependencies: []
		)
	]
)
