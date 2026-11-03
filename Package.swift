// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenMount",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenMountKit", targets: ["OpenMountKit"]),
        .executable(name: "omctl", targets: ["omctl"]),
        .executable(name: "OpenMount", targets: ["OpenMountApp"]),
    ],
    targets: [
        .target(name: "OpenMountKit", path: "Sources/OpenMountKit"),
        .executableTarget(name: "omctl", dependencies: ["OpenMountKit"], path: "Sources/omctl"),
        .executableTarget(name: "OpenMountApp", dependencies: ["OpenMountKit"], path: "App"),
        .testTarget(name: "OpenMountKitTests", dependencies: ["OpenMountKit"], path: "Tests/OpenMountKitTests"),
    ],
    swiftLanguageModes: [.v5]
)
