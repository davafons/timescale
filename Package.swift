// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Timescale",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TimescaleCore", targets: ["TimescaleCore"]),
    .executable(name: "Timescale", targets: ["Timescale"]),
  ],
  targets: [
    .target(name: "TimescaleCore"),
    .executableTarget(name: "Timescale", dependencies: ["TimescaleCore"]),
    .testTarget(name: "TimescaleCoreTests", dependencies: ["TimescaleCore"]),
  ]
)
