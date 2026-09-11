// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RemoteController",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "RemoteControllerCore",
            targets: ["RemoteControllerCore"]
        ),
        .library(
            name: "RemoteControllerUI",
            targets: ["RemoteControllerUI"]
        ),
        .executable(
            name: "RemoteController",
            targets: ["RemoteController"]
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
            name: "RemoteControllerCore",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources/RemoteControllerCore"
        ),
        .target(
            name: "RemoteControllerUI",
            dependencies: [
                "RemoteControllerCore",
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources/RemoteControllerUI"
        ),
        .executableTarget(
            name: "RemoteController",
            dependencies: [
                "RemoteControllerCore",
                "RemoteControllerUI",
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources/RemoteController"
        ),
        .executableTarget(
            name: "TestRunner",
            dependencies: [
                "RemoteControllerCore"
            ],
            path: "Sources/TestRunner"
        )
    ]
)
