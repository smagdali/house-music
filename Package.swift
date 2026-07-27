// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KaysonicKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "KaysonicKit", targets: ["KaysonicKit"])
    ],
    targets: [
        .target(name: "KaysonicKit", path: "Sources/KaysonicKit"),
        .testTarget(
            name: "KaysonicKitTests",
            dependencies: ["KaysonicKit"],
            path: "Tests/KaysonicKitTests"
        ),
    ]
)
