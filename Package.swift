// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Kodema",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "kodema", targets: ["Kodema"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0"),
        .package(url: "https://github.com/RNCryptor/RNCryptor.git", from: "5.1.0"),
        .package(url: "https://github.com/AliSoftware/OHHTTPStubs.git", from: "9.1.0")
    ],
    targets: [
        .executableTarget(
            name: "Kodema",
            dependencies: ["Yams", "RNCryptor"],
            path: "kodema",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "KodemaTests",
            dependencies: [
                "Kodema",
                .product(name: "OHHTTPStubsSwift", package: "OHHTTPStubs")
            ],
            path: "Tests"
        )
    ]
)
