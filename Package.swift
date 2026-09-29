// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Timescale",
  platforms: [.macOS(.v14), .iOS(.v18)],
  products: [
    .library(name: "TimescaleCore", targets: ["TimescaleCore"]),
    .executable(name: "Timescale", targets: ["Timescale"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6")
  ],
  targets: [
    .target(name: "TimescaleCore"),
    .executableTarget(name: "Timescale", dependencies: ["TimescaleCore", "Sparkle"]),
    .testTarget(name: "TimescaleCoreTests", dependencies: ["TimescaleCore"]),
  ]
)
