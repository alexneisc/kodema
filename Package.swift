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
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0")
    ],
    targets: [
        .executableTarget(
            name: "Kodema",
            dependencies: ["Yams"],
            path: "kodema",
            sources: [
                "core.swift",
                "Version.swift"
            ]
        )
    ]
)
