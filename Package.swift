// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "scrap",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ScrapApp", targets: ["ScrapApp"]),
        .executable(name: "scrap-cli", targets: ["scrap-cli"]),
        .library(name: "ScrapCore", targets: ["ScrapCore"]),
    ],
    targets: [
        .target(name: "ScrapCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "ScrapApp", dependencies: ["ScrapCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "scrap-cli", dependencies: ["ScrapCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ScrapCoreTests", dependencies: ["ScrapCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
