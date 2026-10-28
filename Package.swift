// swift-tools-version:5.9
// Test harness for the pure (no CGS / AppKit) logic in SpaceSwitcher/SpaceSwitcher/Logic.
// The app itself is built from the Xcode project; this package exists so the logic can be
// unit-tested without touching real Spaces:  swift test --disable-sandbox
import PackageDescription

let package = Package(
    name: "SpaceLogic",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SpaceLogic", targets: ["SpaceLogic"])],
    targets: [
        .target(name: "SpaceLogic", path: "SpaceSwitcher/SpaceSwitcher/Logic"),
        .testTarget(name: "SpaceLogicTests", dependencies: ["SpaceLogic"], path: "Tests/SpaceLogicTests"),
    ]
)
