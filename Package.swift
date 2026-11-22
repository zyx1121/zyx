// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Zyx",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Zyx", targets: ["Zyx"]),
    ],
    targets: [
        // The pmset and sudoers logic, without UI, so it is tested on its own.
        .target(name: "ZyxKit"),
        // stick's macOS desktop daemon, kept as close to stick's copy as
        // possible, so it builds in the Swift 5 language mode as stick does.
        .target(name: "Stickd", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Zyx", dependencies: ["ZyxKit", "Stickd"]),
        .testTarget(name: "ZyxKitTests", dependencies: ["ZyxKit"]),
    ]
)
