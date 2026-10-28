// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VistoCore",
    platforms: [.macOS(.v13), .iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "VistoCore", targets: ["VistoCore"])],
    targets: [
        .target(name: "VistoCore"),
        .testTarget(name: "VistoCoreTests", dependencies: ["VistoCore"])
    ]
)
