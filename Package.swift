// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PowerFlow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "PowerFlowApp", path: "Sources/PowerFlowApp")
    ]
)
