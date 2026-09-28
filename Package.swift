// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SiliconPulse",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SiliconPulse", targets: ["SiliconPulse"])],
    targets: [
        .executableTarget(
            name: "SiliconPulse",
            path: "SiliconPulse",
            resources: [.copy("Resources")],
            linkerSettings: [
                .linkedFramework("IOKit"), .linkedFramework("CoreWLAN"),
                .linkedFramework("Charts"), .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(name: "SiliconPulseTests", dependencies: ["SiliconPulse"], path: "Tests")
    ]
)
