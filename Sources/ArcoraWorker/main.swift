import Foundation
import ArcoraCore
#if os(macOS)
import Darwin
#else
import Glibc
#endif

// Minimal independent native worker: a decoding fault cannot crash the SwiftUI process.
// This executable is never a network service and has no listening socket.
func emit(_ value:WorkerMessage) {
    if var data=try? JSONEncoder().encode(value) { data.append(10); try? FileHandle.standardOutput.write(contentsOf:data) }
}
func main() throws {
    let args=Array(CommandLine.arguments.dropFirst())
    guard args.count>=2 else { throw ArchiveError.invalid("Usage: arcora-worker list|extract|test ARCHIVE [DESTINATION] [--max-bytes N] [--max-entries N] [--selection FILE]") }
    let action=args[0],source=URL(fileURLWithPath:args[1])
    func option(_ key:String)->String? { guard let i=args.firstIndex(of:key),args.indices.contains(i+1) else{return nil}; return args[i+1] }
    var limits=SafetyLimits()
    if let s=option("--max-bytes"),let n=UInt64(s) { limits.maxExpandedBytes=n }
    if let s=option("--max-entries"),let n=Int(s),n>0 { limits.maxEntries=n }
    var input=try FileHandle.standardInput.read(upToCount:4096) ?? Data()
    defer { input.resetBytes(in:0..<input.count) }
    let first=input.prefix(while:{$0 != 10 && $0 != 13})
    let secret=first.isEmpty ? nil : try Secret(String(decoding:first,as:UTF8.self))
    defer { secret?.clear() }
    var selection:Set<String>?
    if let file=option("--selection") {
        let text=try String(contentsOfFile:file,encoding:.utf8)
        selection=Set(try text.split(separator:"\n").map{try PathSafety.canonicalEntry(String($0))})
    }
    switch action {
    case "list":
        _=try NativeArchive.list(source,password:secret,limits:limits,sink:{emit(WorkerMessage(kind:"entry",entry:$0))})
    case "test","extract":
        let destination:URL?
        if action=="extract" {
            guard args.count>=3,!args[2].hasPrefix("--") else { throw ArchiveError.invalid("Missing extraction directory.") }
            destination=URL(fileURLWithPath:args[2])
        } else { destination=nil }
        let throttle=ProgressThrottle()
        try NativeArchive.read(source,to:destination,password:secret,selection:selection,limits:limits,progress:{ value in
            if throttle.shouldEmit() { emit(WorkerMessage(kind:"progress",progress:value)) }
        })
    default: throw ArchiveError.invalid("Unknown worker action.")
    }
    emit(WorkerMessage(kind:"done",message:NativeArchive.version))
}
final class ProgressThrottle: @unchecked Sendable {
    private let lock=NSLock(); private var last=Date.distantPast
    func shouldEmit()->Bool { lock.lock(); defer{lock.unlock()}; if Date().timeIntervalSince(last)<0.1{return false}; last=Date(); return true }
}
do { try main() } catch {
    emit(WorkerMessage(kind:"error",message:error.localizedDescription)); exit(2)
}
