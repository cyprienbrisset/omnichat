// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OmniRouteKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OmniRouteKit", targets: ["OmniRouteKit"])
    ],
    targets: [
        .target(name: "OmniRouteKit"),
        .testTarget(name: "OmniRouteKitTests", dependencies: ["OmniRouteKit"])
    ]
)
