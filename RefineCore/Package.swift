// swift-tools-version:5.9
// The platform-neutral core shared by RefineBar (macOS) and the Refine keyboard (iOS):
// runs Refine.popclipext's prompt.js / redact.js in JavaScriptCore and talks to Groq.
import PackageDescription

let package = Package(
    name: "RefineCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "RefineCore", targets: ["RefineCore"])
    ],
    targets: [
        .target(name: "RefineCore", path: "Sources/RefineCore"),
        .testTarget(name: "RefineCoreTests", dependencies: ["RefineCore"], path: "Tests/RefineCoreTests"),
    ]
)
