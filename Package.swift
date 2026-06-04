// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnvilNetwork",
    platforms: [.iOS(.v18), .macOS(.v15), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [
        .library(name: "AnvilNetwork", targets: ["AnvilNetwork"]),
    ],
    targets: [
        .target(name: "AnvilNetwork"),
        .testTarget(name: "AnvilNetworkTests", dependencies: ["AnvilNetwork"]),
    ],
    swiftLanguageModes: [.v6]
)
