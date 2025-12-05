// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MasterDataGenerator",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MasterDataGenerator", targets: ["MasterDataGenerator"])
    ],
    targets: [
        .executableTarget(
            name: "MasterDataGenerator",
            path: "Sources",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
