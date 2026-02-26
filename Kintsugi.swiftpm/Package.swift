// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kintsugi",
    platforms: [.iOS(.v17)],
    targets: [
        .executableTarget(
            name: "Kintsugi",
            path: "Kintsugi",
            resources: []
        )
    ]
)
