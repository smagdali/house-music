// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HouseMusicKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "HouseMusicKit", targets: ["HouseMusicKit"])
    ],
    targets: [
        .target(name: "HouseMusicKit", path: "Sources/HouseMusicKit"),
        .testTarget(
            name: "HouseMusicKitTests",
            dependencies: ["HouseMusicKit"],
            path: "Tests/HouseMusicKitTests"
        ),
    ]
)
