// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "remote-input-mac",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RemoteCore", targets: ["RemoteCore"]),
        .executable(name: "remoteinput", targets: ["remoteinput"]),
        .executable(name: "RemoteInputApp", targets: ["RemoteInputApp"]),
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
            name: "remoteinput",
            dependencies: ["RemoteCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "RemoteInputApp",
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
