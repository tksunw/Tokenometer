// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TokenometerCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "TokenometerCore", targets: ["TokenometerCore"]),
        .library(name: "TokenometerUI", targets: ["TokenometerUI"]),
        .executable(name: "tokenometerctl", targets: ["tokenometerctl"]),
        .executable(name: "mockups", targets: ["mockups"]),
    ],
    targets: [
        .target(name: "TokenometerCore"),
        .target(name: "TokenometerUI", dependencies: ["TokenometerCore"]),
        .executableTarget(name: "tokenometerctl", dependencies: ["TokenometerCore"]),
        .executableTarget(name: "mockups", dependencies: ["TokenometerCore", "TokenometerUI"]),
        .testTarget(
            name: "TokenometerCoreTests",
            dependencies: ["TokenometerCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
