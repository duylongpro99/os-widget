// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OSWidgetKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OSWidgetKit", targets: ["OSWidgetKit"]),
    ],
    targets: [
        .target(name: "OSWidgetKit"),
        .testTarget(name: "OSWidgetKitTests", dependencies: ["OSWidgetKit"], resources: [.copy("Fixtures")]),
    ]
)
