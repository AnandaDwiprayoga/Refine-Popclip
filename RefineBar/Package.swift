// swift-tools-version:5.9
// Build with ./build.sh (wraps the binary in RefineBar.app). `swift build` alone
// gives a bare binary without the bundled JS, mic permission text or menu bar mode.
import PackageDescription

let package = Package(
    name: "RefineBar",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../RefineCore")
    ],
    targets: [
        .executableTarget(
            name: "RefineBar",
            dependencies: [.product(name: "RefineCore", package: "RefineCore")],
            path: "Sources/RefineBar"
        )
    ]
)
