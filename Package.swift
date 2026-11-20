// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StudyNotch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "StudyNotch", path: "Sources/StudyNotch")
    ]
)
