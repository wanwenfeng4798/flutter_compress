// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_compress_pro",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15"),
    ],
    products: [
        .library(name: "flutter-compress-pro", targets: ["flutter_compress_pro"]),
    ],
    dependencies: [
        // Provided by Flutter's SPM integration as a sibling under
        // `Flutter/ephemeral/Packages/.packages/FlutterFramework`.
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "flutter_compress_pro",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
    ]
)
