// swift-tools-version: 5.9
// NOTE: This Package.swift enables `swift build` for the library logic.
// The full SwiftUI app (with AppKit, Carbon, and @main entry point) requires
// `xcodebuild` via VaultClip.xcodeproj. This manifest is primarily useful for
// building and testing the non-UI components (crypto, storage, memory protection).
import PackageDescription

let package = Package(
    name: "VaultClip",
    platforms: [.macOS(.v12)],
    targets: [
        .target(
            name: "VaultClip",
            path: "VaultClip",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "VaultClipTests",
            dependencies: ["VaultClip"],
            path: "VaultClipTests"
        )
    ]
)
