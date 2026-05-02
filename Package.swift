// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LocalBlastStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LocalBlastCore", targets: ["LocalBlastCore"]),
        .executable(name: "LocalBlastStudio", targets: ["LocalBlastStudio"]),
        .executable(name: "LocalBlastSmokeTests", targets: ["LocalBlastSmokeTests"])
    ],
    targets: [
        .target(
            name: "LocalBlastCore",
            path: "Sources/LocalBlastCore"
        ),
        .executableTarget(
            name: "LocalBlastStudio",
            dependencies: ["LocalBlastCore"],
            path: "Sources/LocalBlastStudio"
        ),
        .executableTarget(
            name: "LocalBlastSmokeTests",
            dependencies: ["LocalBlastCore"],
            path: "Sources/LocalBlastSmokeTests"
        )
    ]
)
