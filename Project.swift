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
	sources: ["Sources/**/*"]
)

let project = Project(
	name: "RawH264DataConverter",
	targets: [
		target
	]
)
