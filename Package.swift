// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Trako",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Trako",
            targets: ["Trako"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Trako"
        )
    ]
)
