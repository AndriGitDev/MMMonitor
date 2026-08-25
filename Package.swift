// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MMMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MMMonitor", targets: ["MMMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "MMMonitor",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications")
            ]
        )
    ]
)
