// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LaunchDeck",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "LaunchDeck",
            targets: ["LaunchDeck"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "LaunchDeck"
        ),
    ]
)
