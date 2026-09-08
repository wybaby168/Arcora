// swift-tools-version: 5.10
import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
#if os(macOS)
let archiveCSettings: [CSetting] = [.headerSearchPath("../../Vendor/libarchive/include")]
let archiveLinkSettings: [LinkerSetting] = [
    .unsafeFlags([packageRoot + "/Vendor/libarchive/lib/libarchive.a", packageRoot + "/Vendor/libarchive/lib/liblzma.a"]),
    .linkedLibrary("z"), .linkedLibrary("bz2"), .linkedLibrary("iconv")
]
#else
let archiveCSettings: [CSetting] = []
let archiveLinkSettings: [LinkerSetting] = [.linkedLibrary("archive")]
#endif

let package = Package(
    name: "Arcora",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArcoraCore", targets: ["ArcoraCore"]),
        .executable(name: "Arcora", targets: ["Arcora"]),
        .executable(name: "arcora-worker", targets: ["ArcoraWorker"]),
        .executable(name: "arcora-cli", targets: ["ArcoraCLI"])
    ],
    targets: [
        .target(name: "CArcora", cSettings: archiveCSettings, linkerSettings: archiveLinkSettings),
        .target(name: "ArcoraCore", dependencies: ["CArcora"]),
        .executableTarget(name: "Arcora", dependencies: ["ArcoraCore"], resources: [.process("Resources")]),
        .executableTarget(name: "ArcoraWorker", dependencies: ["ArcoraCore"]),
        .executableTarget(name: "ArcoraCLI", dependencies: ["ArcoraCore"]),
        .testTarget(name: "ArcoraCoreTests", dependencies: ["ArcoraCore"], resources: [.copy("Fixtures")])
    ]
)
