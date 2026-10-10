// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SuperConvertMac",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SCCore", targets: ["SCCore"]),
        .executable(name: "sc4", targets: ["sc4"]),
    ],
    targets: [
        .target(name: "SCCore"),
        .executableTarget(name: "sc4", dependencies: ["SCCore"]),
        .testTarget(name: "SCCoreTests", dependencies: ["SCCore"]),
    ]
)
