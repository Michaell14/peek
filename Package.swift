// swift-tools-version: 5.9
import PackageDescription

// BlinkCore is plain Foundation and builds anywhere (including Linux, which is
// where most of its tests run in CI). The app itself needs AppKit and WebKit.
var products: [Product] = [
    .library(name: "BlinkCore", targets: ["BlinkCore"]),
]

var targets: [Target] = [
    .target(name: "BlinkCore", path: "Sources/BlinkCore"),
    // Dev tool: prints the JavaScript injected into pages so it can be tested
    // in a real browser (see Tests/Browser).
    .executableTarget(
        name: "blink-scripts",
        dependencies: ["BlinkCore"],
        path: "Sources/blink-scripts"
    ),
    .testTarget(
        name: "BlinkCoreTests",
        dependencies: ["BlinkCore"],
        path: "Tests/BlinkCoreTests"
    ),
]

#if os(macOS)
products.append(.executable(name: "Blink", targets: ["Blink"]))
targets.append(
    .executableTarget(
        name: "Blink",
        dependencies: ["BlinkCore"],
        path: "Sources/Blink"
    )
)
#endif

let package = Package(
    name: "Blink",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
