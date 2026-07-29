// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NovaLaunchKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NovaLaunchKit", targets: ["NovaLaunchKit"])
    ],
    targets: [
        .target(
            name: "NovaLaunchKit",
            dependencies: [],
            path: "Sources/NovaLaunchKit"
        )
    ]
)
