// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeskCat",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DeskCat", targets: ["DeskCat"])],
    targets: [
        .executableTarget(name: "DeskCat", path: "Sources/DeskCat", resources: [.process("Resources")])
    ]
)
