// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Sendle",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "SendleDomain"),
    .target(name: "SendlePersistence", dependencies: ["SendleDomain"]),
    .target(
      name: "SendleAppleBooks",
      dependencies: ["SendleDomain"],
      linkerSettings: [.linkedLibrary("sqlite3")]
    ),
    .target(name: "SendleEPUB", dependencies: ["SendleDomain"]),
    .target(name: "SendleCovers", dependencies: ["SendleDomain", "SendleEPUB"]),
    .target(name: "SendleUI", dependencies: ["SendleDomain"]),
    .target(name: "SMTPKit"),
    .executableTarget(
      name: "Sendle",
      dependencies: [
        "SendleDomain", "SendleUI", "SendlePersistence", "SendleAppleBooks", "SendleEPUB",
        "SendleCovers",
      ]
    ),
    .target(
      name: "SendleTestSupport",
      dependencies: ["SendleDomain", "SMTPKit"],
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
    .testTarget(
      name: "SendleAppleBooksTests",
      dependencies: ["SendleAppleBooks", "SendleTestSupport"]
    ),
    .testTarget(
      name: "SendleEPUBTests",
      dependencies: ["SendleEPUB", "SendleTestSupport"]
    ),
    .testTarget(
      name: "SendleCoversTests",
      dependencies: ["SendleCovers", "SendleTestSupport"]
    ),
    .testTarget(name: "SMTPKitTests", dependencies: ["SMTPKit", "SendleTestSupport"]),
    .testTarget(
      name: "SendleUITests",
      dependencies: ["SendleUI", "SendleTestSupport"]
    ),
  ]
)
