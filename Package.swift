// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "HostDeck",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HostDeck", targets: ["HostDeck"])
    ],
    targets: [
        .systemLibrary(
            name: "CLibSSH2",
            pkgConfig: "libssh2",
            providers: [
                .brew(["libssh2"])
            ]
        ),
        .executableTarget(
            name: "HostDeck",
            dependencies: ["CLibSSH2"],
            path: "Sources/HostDeck",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
