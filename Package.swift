// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ontop",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "ontop",
            path: "Sources/ontop"
        ),
        .testTarget(
            name: "ontopTests",
            dependencies: ["ontop"],
            path: "Tests/ontopTests"
        ),
    ]
)
