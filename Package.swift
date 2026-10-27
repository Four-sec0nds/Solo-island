// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [.library(name: "IslandCore", targets: ["IslandCore"])]
var targets: [Target] = [
    .target(name: "IslandCore"),
    .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"])
]
#if os(macOS)
products.append(.executable(name: "SoloIsland", targets: ["IslandApp"]))
targets.append(.target(name: "IslandPlatform", dependencies: ["IslandCore"]))
targets.append(.executableTarget(name: "IslandApp", dependencies: ["IslandCore", "IslandPlatform"]))
targets.append(.testTarget(name: "IslandPlatformTests", dependencies: ["IslandPlatform", "IslandCore"]))
#endif

let package = Package(name: "SoloIsland", platforms: [.macOS(.v14)], products: products, targets: targets)
