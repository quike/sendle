// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Sendle",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "SendleDomain"),
    .target(name: "SendlePersistence", dependencies: ["SendleDomain"]),
    .target(
      name: "SendleTestSupport",
      dependencies: ["SendleDomain"],
      path: "Tests/SendleTestSupport"
    ),
    .testTarget(
      name: "SendleDomainTests",
      dependencies: ["SendleDomain", "SendleTestSupport"]
    ),
    .testTarget(
      name: "SendlePersistenceTests",
      dependencies: ["SendlePersistence", "SendleTestSupport"]
    ),
  ]
)
