// swift-tools-version: 5.9
import PackageDescription

// GanderCore is plain Foundation and builds anywhere (including Linux, which is
// where most of its tests run in CI). The app itself needs AppKit and WebKit.
var products: [Product] = [
    .library(name: "GanderCore", targets: ["GanderCore"]),
]

var targets: [Target] = [
    .target(name: "GanderCore", path: "Sources/GanderCore"),
    // Dev tool: prints the JavaScript injected into pages so it can be tested
    // in a real browser (see Tests/Browser).
    .executableTarget(
        name: "gander-scripts",
        dependencies: ["GanderCore"],
        path: "Sources/gander-scripts"
    ),
    .testTarget(
        name: "GanderCoreTests",
        dependencies: ["GanderCore"],
        path: "Tests/GanderCoreTests"
    ),
]

#if os(macOS)
products.append(.executable(name: "Gander", targets: ["Gander"]))
targets.append(
    .executableTarget(
        name: "Gander",
        dependencies: ["GanderCore"],
        path: "Sources/Gander"
    )
)
#endif

let package = Package(
    name: "Gander",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
