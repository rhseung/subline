// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Subline",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "subline", targets: ["Subline"])
    ],
    targets: [
        .executableTarget(
            name: "Subline"
        )
    ]
)
