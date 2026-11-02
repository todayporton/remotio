// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "remotio",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RemoteCore", targets: ["RemoteCore"]),
        .executable(name: "remotio", targets: ["remotio"]),
        .executable(name: "RemotioApp", targets: ["RemotioApp"]),
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
            name: "remotio",
            dependencies: ["RemoteCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "RemotioApp",
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
