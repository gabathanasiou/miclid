// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MicLid",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MicLid", targets: ["MicLid"])
    ],
    targets: [
        .executableTarget(
            name: "MicLid",
            path: "Sources/MicLid"
        ),
        .testTarget(
            name: "MicLidTests",
            dependencies: ["MicLid"],
            path: "Tests/MicLidTests"
        )
    ]
)
