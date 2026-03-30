// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "layerkey",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "LayerKeyHID",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(
            name: "layerkey",
            dependencies: ["LayerKeyHID"]
        ),
    ]
)
