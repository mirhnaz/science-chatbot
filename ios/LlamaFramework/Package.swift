// swift-tools-version:5.9
// Wraps llama.cpp's prebuilt Apple framework (the engine Ollama also uses).
// Pinned to one release; update the tag and checksum together. The checksum
// is the zip's SHA-256 from the GitHub release page.
import PackageDescription

let package = Package(
    name: "LlamaFramework",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "LlamaFramework", targets: ["llama"])],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11200/llama-b11200-xcframework.zip",
            checksum: "c62cae37316b12938cde3224493e008d121635bf759ddd08fbcdd587b3b8808c"
        ),
    ]
)
