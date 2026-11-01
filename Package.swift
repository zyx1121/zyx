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
        .executableTarget(name: "Zyx", dependencies: ["ZyxKit"]),
        .testTarget(name: "ZyxKitTests", dependencies: ["ZyxKit"]),
    ]
)
