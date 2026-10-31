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
targets.append(.target(name: "IslandAccessibility", publicHeadersPath: "include"))
targets.append(.executableTarget(name: "IslandApp", dependencies: ["IslandCore", "IslandPlatform", "IslandAccessibility"]))
targets.append(.testTarget(name: "IslandPlatformTests", dependencies: ["IslandPlatform", "IslandCore", "IslandAccessibility"]))
#endif

let package = Package(name: "SoloIsland", platforms: [.macOS(.v14)], products: products, targets: targets)
