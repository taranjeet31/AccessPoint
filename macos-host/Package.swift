// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RemoteHost",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "RemoteHost",
            targets: ["RemoteHost"]
        ),
        .executable(
            name: "TestRunner",
            targets: ["TestRunner"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC.git", from: "128.0.0")
    ],
    targets: [
        .target(
            name: "RemoteHostCore",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources/RemoteHostCore"
        ),
        .executableTarget(
            name: "RemoteHost",
            dependencies: [
                "RemoteHostCore",
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources/RemoteHost"
        ),
        .executableTarget(
            name: "TestRunner",
            dependencies: [
                "RemoteHostCore"
            ],
            path: "Sources/TestRunner"
        )
    ]
)
