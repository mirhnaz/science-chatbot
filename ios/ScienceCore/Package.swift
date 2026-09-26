// swift-tools-version:5.9
// Pure tutor logic shared by the app. It has no UI or model code, so
// `swift test` can check it quickly on a Mac without an iPad.
import PackageDescription

let package = Package(
    name: "ScienceCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ScienceCore", targets: ["ScienceCore"])],
    targets: [
        .target(name: "ScienceCore"),
        .testTarget(name: "ScienceCoreTests", dependencies: ["ScienceCore"]),
    ]
)
