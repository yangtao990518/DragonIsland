// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DragonDomain",
    platforms: [.macOS(.v13)],
    products: [.library(name: "DragonDomain", targets: ["DragonDomain"])],
    targets: [
        .target(name: "DragonDomain", path: "Shared/Models"),
        .testTarget(name: "DragonDomainTests", dependencies: ["DragonDomain"],
                    path: "Tests/DragonDomainTests")
    ]
)
