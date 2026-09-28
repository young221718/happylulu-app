// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HappyLulu",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "HappyLulu", targets: ["AfterSix"])],
    targets: [
        .target(name: "AfterSixCore"),
        .executableTarget(name: "AfterSix", dependencies: ["AfterSixCore"]),
        .executableTarget(name: "AfterSixChecks", dependencies: ["AfterSixCore"], path: "Tests/AfterSixCoreTests")
    ]
)
