// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Peperete",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "peperete", targets: ["PepereteCLI"])
    ],
    targets: [
        .target(name: "PepereteCore"),
        .executableTarget(name: "PepereteCLI", dependencies: ["PepereteCore"]),
        .testTarget(name: "PepereteCoreTests", dependencies: ["PepereteCore"])
    ]
)
