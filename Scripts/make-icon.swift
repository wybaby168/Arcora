#!/usr/bin/swift
// Compile the native Tahoe icon stack and its legacy ICNS together.
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("Icon build failed: " + message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("Usage: make-icon.swift OUTPUT_DIRECTORY/Arcora.icns (also writes Assets.car)")
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
guard destination.lastPathComponent == "Arcora.icns" else {
    fail("Use Arcora.icns so the icon name agrees with CFBundleIconName.")
}
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("Configuration/Arcora.icon")
guard FileManager.default.fileExists(atPath: source.appendingPathComponent("icon.json").path) else {
    fail("The checked-in Icon Composer document is missing.")
}
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Arcora-icon-" + UUID().uuidString)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: temporary) }

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
process.arguments = [
    "actool", source.path, "--compile", temporary.path,
    "--output-format", "human-readable-text", "--warnings", "--errors", "--notices",
    "--app-icon", "Arcora", "--output-partial-info-plist", temporary.appendingPathComponent("icon-info.plist").path,
    "--platform", "macosx", "--minimum-deployment-target", "14.0", "--target-device", "mac",
    "--standalone-icon-behavior", "all"
]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fail("actool failed; select Xcode 26 or later.") }
let infoData = try Data(contentsOf: temporary.appendingPathComponent("icon-info.plist"))
guard let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
      info["CFBundleIconName"] as? String == "Arcora",
      info["CFBundleIconFile"] as? String == "Arcora" else {
    fail("The compiler did not declare the expected native app icon.")
}
for filename in ["Arcora.icns", "Assets.car"] {
    let data = try Data(contentsOf: temporary.appendingPathComponent(filename))
    guard !data.isEmpty else { fail("Empty compiled icon resource: " + filename) }
    try data.write(to: destination.deletingLastPathComponent().appendingPathComponent(filename), options: .atomic)
}
print("Built native Arcora icon stack and complete legacy ICNS")
