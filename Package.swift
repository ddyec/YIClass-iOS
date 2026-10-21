// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YIClassCore",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "YIClassCore", targets: ["YIClassCore"])],
    targets: [
        .target(name: "YIClassCore", path: "Sources/Core"),
        .testTarget(name: "YIClassCoreTests", dependencies: ["YIClassCore"], path: "Tests/Core")
    ]
)
