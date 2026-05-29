// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BunnyshellApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BunnyshellApp", targets: ["BunnyshellApp"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "bunnyshell_coreFFI",
            path: "Sources/bunnyshell_coreFFI",
            publicHeadersPath: "include"
        ),
        .target(
            name: "ObjCExceptionCatcher",
            path: "Sources/ObjCExceptionCatcher",
            publicHeadersPath: "include"
        ),
        .target(
            name: "BunnyshellCore",
            dependencies: ["bunnyshell_coreFFI"],
            path: "Sources/BunnyshellCore",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "../target/debug",
                    "-l", "bunnyshell_core"
                ]),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "BunnyshellApp",
            dependencies: [
                "BunnyshellCore",
                "ghostty-internal-fat",
                "ObjCExceptionCatcher"
            ],
            path: "Sources/BunnyshellApp",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("GameController")
            ]
        ),
        .binaryTarget(
            name: "ghostty-internal-fat",
            path: "Frameworks/ghostty-internal-fat.xcframework"
        )
    ]
)
