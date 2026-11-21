// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tessera",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TesseraCore"),
        .executableTarget(name: "Tessera", dependencies: ["TesseraCore"]),
        .testTarget(name: "TesseraCoreTests", dependencies: ["TesseraCore"]),
    ],
    swiftLanguageModes: [.v5]
)
