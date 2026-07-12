// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dooodle",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Dooodle",
            path: "Sources/Dooodle"
        )
    ]
)
