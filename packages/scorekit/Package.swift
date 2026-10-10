// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScoreKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ScoreKit", targets: ["ScoreKit"])
    ],
    targets: [
        .target(
            name: "ScoreKit",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "ScoreKitTests",
            dependencies: ["ScoreKit"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
