// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "mkbd",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MKbd", targets: ["MKbd"]),
        .executable(name: "mkbdctl", targets: ["mkbdctl"]),
        .library(name: "KeyboardCore", targets: ["KeyboardCore"]),
    ],
    targets: [
        .target(
            name: "KeyboardCore",
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "MKbd",
            dependencies: ["KeyboardCore"]
        ),
        .executableTarget(
            name: "mkbdctl",
            dependencies: ["KeyboardCore"]
        ),
        .testTarget(
            name: "KeyboardCoreTests",
            dependencies: ["KeyboardCore"]
        ),
    ]
)
