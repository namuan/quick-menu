// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "quick-menu",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "QuickMenu", targets: ["QuickMenu"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "QuickMenu",
            swiftSettings: [],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        )
    ]
)
