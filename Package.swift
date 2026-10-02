// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ColimaMini",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "ColimaMini", targets: ["ColimaMini"])],
  targets: [
    .target(name: "ColimaCore", resources: [.copy("Resources/docker-sweep.py")]),
    .executableTarget(name: "ColimaMini", dependencies: ["ColimaCore"]),
    .testTarget(
      name: "ColimaCoreTests", dependencies: ["ColimaCore"], resources: [.copy("Fixtures")]),
  ],
  swiftLanguageModes: [.v5]
)
