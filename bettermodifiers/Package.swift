// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "bettermodifiers",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4"),
    ],
    targets: [
        .target(
            name: "BetterModifiersHID",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(
            name: "bettermodifiers",
            dependencies: [
                "BetterModifiersHID",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
    ]
)
