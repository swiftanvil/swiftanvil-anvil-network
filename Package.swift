// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnvilNetwork",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "AnvilNetwork", targets: ["AnvilNetwork"]),
    ],
    targets: [
        .target(name: "AnvilNetwork"),
        .testTarget(name: "AnvilNetworkTests", dependencies: ["AnvilNetwork"]),
    ],
    swiftLanguageModes: [.v6]
)
