// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SiliconPulse",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SiliconPulse", targets: ["SiliconPulse"])],
    targets: [
        .target(name: "FastTreeCore", path: "Native/FastTreeCore", exclude: ["LICENSE"], publicHeadersPath: "include"),
        .executableTarget(
            name: "SiliconPulse",
            dependencies: ["FastTreeCore"],
            path: "SiliconPulse",
            exclude: ["Workbench/PortPeek-LICENSE.txt"],
            resources: [.copy("Resources")],
            linkerSettings: [
                .linkedFramework("IOKit"), .linkedFramework("CoreWLAN"),
                .linkedFramework("Charts"), .linkedFramework("ServiceManagement"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(name: "SiliconPulseTests", dependencies: ["SiliconPulse"], path: "Tests")
    ]
)
