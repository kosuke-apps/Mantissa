// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Mantissa",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "MantissaCore", targets: ["MantissaCore"])
  ],
  targets: [
    .target(name: "MantissaCore"),
    .testTarget(
      name: "MantissaCoreTests",
      dependencies: ["MantissaCore"],
      resources: [.copy("Resources")]
    ),
  ]
)
