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
        .package(url: "https://github.com/RNCryptor/RNCryptor.git", from: "5.1.0")
    ],
    targets: [
        .executableTarget(
            name: "Kodema",
            dependencies: ["Yams", "RNCryptor"],
            path: "kodema",
            sources: [
                "core.swift",
                "Version.swift"
            ]
        )
    ]
)
