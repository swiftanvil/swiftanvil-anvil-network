// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnvilNetwork",
    platforms: [.iOS(.v18), .macOS(.v15), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [
        .library(name: "AnvilNetwork", targets: ["AnvilNetwork"]),
    ],
    dependencies: [
        .package(path: "../swiftanvil-anvil-core"),
    ],
    targets: [
        .target(name: "AnvilNetwork", dependencies: [
            .product(name: "AnvilCore", package: "swiftanvil-anvil-core"),
        ]),
        .testTarget(name: "AnvilNetworkTests", dependencies: ["AnvilNetwork"]),
    ],
    swiftLanguageModes: [.v6]
)
