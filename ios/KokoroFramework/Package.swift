// swift-tools-version:5.9
// Kokoro text-to-speech for Read aloud, through sherpa-onnx's prebuilt iOS
// framework and the ONNX Runtime it runs on. Pinned like LlamaFramework:
// URLs and checksums copied from sherpa-onnx v1.13.8's own Package.swift and
// onnxruntime-libs 1.28.2. Update each URL and checksum together.
import PackageDescription

let package = Package(
    name: "KokoroFramework",
    platforms: [.iOS(.v17)],
    products: [.library(name: "KokoroFramework", targets: ["KokoroFramework"])],
    targets: [
        .binaryTarget(
            name: "SherpaOnnxC",
            url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v1.13.8-ios-static.xcframework.zip",
            checksum: "6b8e769cb153343270fdccbe92e3b3db0d1c421d67fa0989ab01fdf5b2fcf2de"
        ),
        .binaryTarget(
            name: "onnxruntime",
            url: "https://github.com/csukuangfj/onnxruntime-libs/releases/download/v1.28.2/onnxruntime-ios-static-xcframework-1.28.2.xcframework.zip",
            checksum: "2c2299acbb461d26d4bac4bc85985d40e7c7177ed6072703ae0846d88b0b4599"
        ),
        // A small Swift wrapper over the C functions Kokoro needs.
        .target(
            name: "KokoroFramework",
            dependencies: ["SherpaOnnxC", "onnxruntime"],
            linkerSettings: [.linkedLibrary("c++")]
        ),
    ]
)
