// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bangs",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Bangs", path: "Sources/Bangs"),
        // Swift Testing (входит в Command Line Tools; XCTest без Xcode недоступен).
        .testTarget(name: "BangsTests", dependencies: ["Bangs"], path: "Tests/BangsTests"),
    ]
)
