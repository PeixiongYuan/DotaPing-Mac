// swift-tools-version: 5.9
import PackageDescription

// scripts/build.sh and scripts/test.sh call swiftc directly and do not need
// this manifest; it is kept for Xcode and `swift build`.
let package = Package(
    name: "DotaPing",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DotaPing", targets: ["DotaPing"])],
    targets: [
        .target(name: "PingCore"),
        .executableTarget(name: "DotaPing", dependencies: ["PingCore"]),
        .executableTarget(name: "PingCoreChecks", dependencies: ["PingCore"], path: "Tests/PingCoreTests")
    ]
)
