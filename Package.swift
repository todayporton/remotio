// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "firetv-remote-mac",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RemoteCore", targets: ["RemoteCore"]),
        .executable(name: "fireremote", targets: ["fireremote"]),
        .executable(name: "FireRemoteApp", targets: ["FireRemoteApp"]),
    ],
    targets: [
        .systemLibrary(
            name: "COpus",
            pkgConfig: "opus",
            providers: [.brew(["opus"])]
        ),
        .target(
            name: "RemoteCore",
            dependencies: ["COpus"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "fireremote",
            dependencies: ["RemoteCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FireRemoteApp",
            dependencies: ["RemoteCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "RemoteCoreTests",
            dependencies: ["RemoteCore", "COpus"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
