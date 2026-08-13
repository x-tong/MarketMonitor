// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarketMonitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MarketMonitor", targets: ["MarketMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "MarketMonitor",
            path: "App"
        ),
        .testTarget(
            name: "MarketMonitorTests",
            dependencies: ["MarketMonitor"],
            path: "Tests"
        ),
    ]
)
