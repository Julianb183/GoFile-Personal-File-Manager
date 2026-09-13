// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoFileManager",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "GoFileManager", targets: ["GoFileManager"])],
    targets: [.executableTarget(name: "GoFileManager")]
)
