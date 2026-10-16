// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WexiLoL",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WexiLoL", targets: ["WexiLoL"])],
    targets: [
        .target(name: "RiftCore", path: "App/RiftCore"),
        .executableTarget(name: "WexiLoL", dependencies: ["RiftCore"], path: "App/RiftOverlay", resources: [.process("Resources")]),
        .testTarget(name: "RiftCoreTests", dependencies: ["RiftCore"], resources: [.copy("Fixtures")])
    ]
)
