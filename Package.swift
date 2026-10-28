// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudePet",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "companion/VistoCore")],
    targets: [
        .executableTarget(name: "ClaudePet", dependencies: [.product(name: "VistoCore", package: "VistoCore")], path: "Sources/ClaudePet")
    ]
)
