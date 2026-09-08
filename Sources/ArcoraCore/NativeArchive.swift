import Foundation
import CArcora

public enum NativeArchive {
    public static var version:String { String(cString:arc_archive_version()) }
    private final class Context {
        var entries:[ArchiveEntry]=[]
        var entrySink:((ArchiveEntry)->Void)?
        var progress:ProgressSink?
        var selected:Set<String>?
        let control:JobControl
        init(control:JobControl) { self.control=control }
    }
    private static func entry(_ c:arc_entry)->ArchiveEntry {
        ArchiveEntry(path:c.path.map{String(cString:$0)} ?? "",size:UInt64(max(0,c.size)),
            modified:c.modified==0 ? nil : Date(timeIntervalSince1970:TimeInterval(c.modified)),
            isDirectory:c.directory != 0,isEncrypted:c.encrypted != 0,isUnsafeType:c.unsafe_type != 0,
            linkTarget:c.link.map{String(cString:$0)})
    }
    public static func list(_ source:URL,password:Secret?=nil,limits:SafetyLimits=SafetyLimits(),control:JobControl=JobControl(),
                            sink:((ArchiveEntry)->Void)?=nil) throws -> [ArchiveEntry] {
        try control.waitWhilePaused()
        let context=Context(control:control); context.entrySink=sink
        let pointer=Unmanaged.passUnretained(context).toOpaque()
        var error=[CChar](repeating:0,count:4096)
        func run(_ p:UnsafePointer<CChar>?)->Int32 {
            source.path.withCString { path in
                arc_archive_list(path,p,UInt64(limits.maxEntries),{ value,raw in
                    guard let value,let raw else { return 1 }
                    let ctx=Unmanaged<Context>.fromOpaque(raw).takeUnretainedValue()
                    if ctx.control.isCancelled { return 1 }
                    let item=NativeArchive.entry(value.pointee)
                    if let sink=ctx.entrySink { sink(item) } else { ctx.entries.append(item) }
                    return 0
                },pointer,&error,error.count)
            }
        }
        let result=password.map{secret in secret.withCString{run($0)}} ?? run(nil)
        try control.check()
        if result != 0 { throw decodeError(String(cString:error),password:password != nil) }
        return context.entries
    }
    public static func read(_ source:URL,to destination:URL?,password:Secret?=nil,selection:Set<String>?=nil,
                            limits:SafetyLimits=SafetyLimits(),control:JobControl=JobControl(),progress:ProgressSink?=nil) throws {
        try control.waitWhilePaused()
        let context=Context(control:control); context.progress=progress; context.selected=selection
        let pointer=Unmanaged.passUnretained(context).toOpaque()
        var error=[CChar](repeating:0,count:4096)
        func run(_ p:UnsafePointer<CChar>?)->Int32 {
            source.path.withCString { path in
                (destination?.path ?? "").withCString { output in
                    arc_archive_read(path,p,output,limits.maxExpandedBytes,UInt64(limits.maxEntries),destination==nil ? 1 : 0,
                    { value,raw in
                        guard let value,let raw else { return 0 }
                        let ctx=Unmanaged<Context>.fromOpaque(raw).takeUnretainedValue()
                        guard let selection=ctx.selected else { return 1 }
                        guard let name=value.pointee.path,let path=try? PathSafety.canonicalEntry(String(cString:name)) else { return 0 }
                        return selection.contains(where:{path==$0 || path.hasPrefix($0+"/")}) ? 1 : 0
                    },
                    { bytes,count,raw in
                        guard let raw else { return 1 }
                        let ctx=Unmanaged<Context>.fromOpaque(raw).takeUnretainedValue()
                        if ctx.control.isCancelled { return 1 }
                        ctx.progress?(ProgressEvent("phase.processing",bytes:bytes,entries:count))
                        return 0
                    },pointer,&error,error.count)
                }
            }
        }
        let result=password.map{secret in secret.withCString{run($0)}} ?? run(nil)
        try control.check()
        if result != 0 { throw decodeError(String(cString:error),password:password != nil) }
    }
    private static func decodeError(_ text:String,password:Bool)->ArchiveError {
        let lower=text.lowercased()
        if lower.contains("passphrase") || lower.contains("password") { return password ? .wrongPassword : .passwordRequired }
        if lower.contains("unsafe") || lower.contains("link/special") { return .unsafePath(text) }
        if lower.contains("limit") { return .resourceLimit(text) }
        return .engine(2,text)
    }
}

public struct WorkerMessage: Codable {
    public var kind:String
    public var entry:ArchiveEntry?
    public var progress:ProgressEvent?
    public var message:String?
    public init(kind:String,entry:ArchiveEntry?=nil,progress:ProgressEvent?=nil,message:String?=nil) {
        self.kind=kind; self.entry=entry; self.progress=progress; self.message=message
    }
}
