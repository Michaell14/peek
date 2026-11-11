// swift-tools-version: 5.9
import PackageDescription

// BlickCore is plain Foundation and builds anywhere (including Linux, which is
// where most of its tests run in CI). The app itself needs AppKit and WebKit.
var products: [Product] = [
    .library(name: "BlickCore", targets: ["BlickCore"]),
]

var targets: [Target] = [
    .target(name: "BlickCore", path: "Sources/BlickCore"),
    // Dev tool: prints the JavaScript injected into pages so it can be tested
    // in a real browser (see Tests/Browser).
    .executableTarget(
        name: "blick-scripts",
        dependencies: ["BlickCore"],
        path: "Sources/blick-scripts"
    ),
    .testTarget(
        name: "BlickCoreTests",
        dependencies: ["BlickCore"],
        path: "Tests/BlickCoreTests"
    ),
]

#if os(macOS)
products.append(.executable(name: "Blick", targets: ["Blick"]))
targets.append(
    .executableTarget(
        name: "Blick",
        dependencies: ["BlickCore"],
        path: "Sources/Blick"
    )
)
#endif

let package = Package(
    name: "Blick",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
