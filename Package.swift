// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpotifyBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SpotifyBar", path: "Sources/SpotifyBar")
    ]
)
