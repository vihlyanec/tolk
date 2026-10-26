// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Takt",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Takt", targets: ["Takt"])],
    targets: [
        .binaryTarget(name: "Sparkle", url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip", checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"),
        .systemLibrary(name: "CSQLite"),
        .target(name: "TaktCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "Takt", dependencies: ["TaktCore", "Sparkle"],
            swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "TaktCoreTests", dependencies: ["TaktCore"]),
        .testTarget(name: "TaktAppTests", dependencies: ["Takt", "TaktCore"])
    ]
)
