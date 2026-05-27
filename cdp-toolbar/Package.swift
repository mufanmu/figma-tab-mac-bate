// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FigmaCDPToolbar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FigmaCDPToolbar",
            path: "Sources/FigmaCDPToolbar",
            resources: [.process("Resources")],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
    ]
)
