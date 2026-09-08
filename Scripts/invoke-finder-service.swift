// Local interactive integration check. Does not change the system clipboard.
// Usage: xcrun swift Scripts/invoke-finder-service.swift "service name" [--wait-for /path/to/output] /path/to/file ...
import AppKit
import Foundation

guard CommandLine.arguments.count>=3 else {
    fputs("Pass a registered service name and local input paths.\n",stderr);exit(2)
}
let application=NSApplication.shared
application.setActivationPolicy(.prohibited)
let board=NSPasteboard.withUniqueName()
defer {board.releaseGlobally()}
var paths=Array(CommandLine.arguments.dropFirst(2))
var expected:URL?
if paths.first == "--wait-for" {
    guard paths.count>=3,paths[1].hasPrefix("/") else {fputs("--wait-for needs an absolute output path and at least one input.\n",stderr);exit(2)}
    expected=URL(fileURLWithPath:paths[1]);paths.removeFirst(2)
    guard !FileManager.default.fileExists(atPath:expected!.path) else {fputs("Expected output must not exist before the test.\n",stderr);exit(2)}
}
guard paths.allSatisfy({$0.hasPrefix("/") && FileManager.default.fileExists(atPath:$0)}) else {
    fputs("Every input must be an existing absolute local path.\n",stderr);exit(2)
}
let urls=paths.map{URL(fileURLWithPath:$0) as NSURL}
guard board.writeObjects(urls) else {fputs("Could not prepare the private file-selection pasteboard.\n",stderr);exit(1)}
guard NSPerformService(CommandLine.arguments[1],board) else {
    fputs("Service request was not accepted. Install the app in Applications, open it once and check Services settings.\n",stderr);exit(1)
}
print("Service accepted the selection. Approve macOS's Run Service prompt if shown.")
if let expected {
    // NSRestricted may defer delivery until a native confirmation is accepted.
    // Keep this test client's private pasteboard alive until the result appears.
    let deadline=Date().addingTimeInterval(120)
    while !FileManager.default.fileExists(atPath:expected.path),Date()<deadline {
        RunLoop.current.run(until:Date().addingTimeInterval(0.2))
    }
    guard FileManager.default.fileExists(atPath:expected.path) else {fputs("No committed output within 120 seconds.\n",stderr);exit(1)}
    print("Committed output exists; inspect and compare its contents separately.")
} else {print("Dispatch only: verify delivery and output separately. Use --wait-for to retain this client's pasteboard while confirming a quick action.")}
