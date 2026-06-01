// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipVault",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClipVault",
            path: "Sources/ClipVault"
        ),
        .testTarget(
            name: "ClipVaultTests",
            dependencies: ["ClipVault"],
            path: "Tests/ClipVaultTests"
        )
    ]
)
