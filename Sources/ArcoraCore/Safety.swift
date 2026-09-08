import Foundation
import CArcora
#if os(macOS)
import Darwin
#else
import Glibc
#endif

public enum PathSafety {
    /// URL.resolvingSymlinksInPath can abbreviate /private/var back to /var.
    /// POSIX realpath gives the same absolute spelling as directory enumeration.
    static func physicalURL(_ url:URL) throws -> URL {
        guard let pointer=url.path.withCString({realpath($0,nil)}) else {throw ArchiveError.io(String(cString:strerror(errno)))}
        defer {free(pointer)}
        return URL(fileURLWithPath:String(cString:pointer))
    }
    public static func canonicalEntry(_ path:String) throws -> String {
        guard !path.unicodeScalars.contains(where:{$0.value<32 || $0.value==127}),
              path.withCString({arc_safe_relative_path($0)}) != 0 else { throw ArchiveError.unsafePath(path) }
        let components=path.split(separator:"/",omittingEmptySubsequences:true).filter{$0 != "."}
        guard !components.isEmpty else { return "." }
        return components.joined(separator:"/")
    }
    public static func validate(_ entries:[ArchiveEntry],limits:SafetyLimits) throws {
        guard entries.count<=limits.maxEntries else { throw ArchiveError.resourceLimit("Too many archive entries.") }
        var paths=[String:Bool](), total:UInt64=0
        for item in entries {
            let path=try canonicalEntry(item.path)
            if path=="." && item.isDirectory { continue }
            guard path != ".", !item.isUnsafeType, item.linkTarget==nil else { throw ArchiveError.unsafePath(item.path) }
            // Conservatively avoid names that collide on a normal case-insensitive APFS volume.
            let key=path.precomposedStringWithCanonicalMapping.lowercased()
            if let oldDirectory=paths[key] {
                guard oldDirectory && item.isDirectory else { throw ArchiveError.collision(item.path) }
            }
            paths[key]=item.isDirectory
            let sum=total.addingReportingOverflow(item.size)
            guard !sum.overflow,sum.partialValue<=limits.maxExpandedBytes else { throw ArchiveError.resourceLimit("Expanded size limit exceeded.") }
            total=sum.partialValue
        }
        // Reject file-vs-directory parent conflicts, regardless of archive entry order.
        for key in paths.keys {
            var parts=key.split(separator:"/")
            while parts.count>1 {
                parts.removeLast()
                if paths[parts.joined(separator:"/")]==false { throw ArchiveError.collision(key) }
            }
        }
    }
    public static func safeFilename(_ name:String) throws {
        guard !name.isEmpty,name != ".",name != "..",name.utf8.count<=180,
              !name.contains("/"),!name.contains("\\"),!name.contains(":"),
              !name.unicodeScalars.contains(where:{$0.value<32 || $0.value==127}) else {
            throw ArchiveError.invalid("Choose a nonempty filename without slashes or control characters (up to 180 UTF-8 bytes).")
        }
    }
    public static func contains(_ parent:URL,_ child:URL) -> Bool {
        let p=parent.standardizedFileURL.path, c=child.standardizedFileURL.path
        return c==p || c.hasPrefix(p=="/" ? "/" : p+"/")
    }
    public static func validateInputs(_ source:[URL],outputParent:URL,limits:SafetyLimits,control:JobControl) throws -> [URL] {
        let fm=FileManager.default
        guard !source.isEmpty else { throw ArchiveError.invalid("No input files selected.") }
        let parent=try physicalURL(outputParent)
        // Foundation enumeration resolves ancestor aliases (/var -> /private/var).
        // Resolve ancestors before relative-path arithmetic, but retain the leaf
        // so a selected symlink still fails the explicit type check below.
        let sorted=Array(Set(try source.map { value -> URL in
            let url=value.standardizedFileURL
            return try physicalURL(url.deletingLastPathComponent()).appendingPathComponent(url.lastPathComponent)
        })).sorted{$0.path.count<$1.path.count}
        var accepted=[URL](),seen=0
        for url in sorted {
            try control.waitWhilePaused()
            let values=try url.resourceValues(forKeys:[.isSymbolicLinkKey,.isDirectoryKey,.isRegularFileKey])
            guard values.isSymbolicLink != true,values.isDirectory==true || values.isRegularFile==true else {
                throw ArchiveError.unsafePath(url.path)
            }
            if accepted.contains(where:{PathSafety.contains($0,url)}) { continue }
            if values.isDirectory==true,contains(try physicalURL(url),parent) {
                throw ArchiveError.invalid("The output directory cannot be inside a selected input folder. Choose its parent or another folder.")
            }
            try safeListPath(url.path)
            accepted.append(url); seen+=1
            guard seen<=limits.maxEntries else { throw ArchiveError.resourceLimit("Too many source files.") }
            _=try canonicalEntry(url.lastPathComponent)
            if values.isDirectory==true {
                var walkError:Error?
                guard let enumerator=fm.enumerator(at:url,includingPropertiesForKeys:[.isSymbolicLinkKey,.isDirectoryKey,.isRegularFileKey],options:[],errorHandler:{_,e in walkError=e; return false}) else {
                    throw ArchiveError.io(url.path)
                }
                for case let file as URL in enumerator {
                    seen+=1
                    guard seen<=limits.maxEntries else { throw ArchiveError.resourceLimit("Too many source files.") }
                    if seen%128==0 { try control.waitWhilePaused() }
                    try safeListPath(file.path)
                    _=try canonicalEntry(String(file.path.dropFirst(url.path.count+1)))
                    let v=try file.resourceValues(forKeys:[.isSymbolicLinkKey,.isDirectoryKey,.isRegularFileKey])
                    if v.isSymbolicLink==true || !(v.isDirectory==true || v.isRegularFile==true) { throw ArchiveError.unsafePath(file.path) }
                }
                if let error=walkError { throw ArchiveError.io(error.localizedDescription) }
            }
        }
        return accepted
    }
    public static func safeListPath(_ path:String) throws {
        if path.unicodeScalars.contains(where:{$0.value<32 || $0.value==127}) { throw ArchiveError.unsafePath(path) }
    }
    @discardableResult
    public static func auditOutput(_ root:URL,limits:SafetyLimits,quarantineSource:URL?=nil,control:JobControl?=nil) throws -> (Int,UInt64) {
        let fm=FileManager.default
        var count=0,bytes:UInt64=0,walkError:Error?
        let keys:Set<URLResourceKey>=[.isSymbolicLinkKey,.isDirectoryKey,.isRegularFileKey,.fileSizeKey]
        guard let iterator=fm.enumerator(at:root,includingPropertiesForKeys:Array(keys),errorHandler:{_,e in walkError=e; return false}) else {
            throw ArchiveError.io(root.path)
        }
        for case let file as URL in iterator {
            count+=1
            _=try canonicalEntry(String(file.path.dropFirst(root.path.count+1)))
            if count%128==0 { try control?.waitWhilePaused() }
            guard count<=limits.maxEntries else { throw ArchiveError.resourceLimit("Too many extracted files.") }
            let v=try file.resourceValues(forKeys:keys)
            if v.isSymbolicLink==true || !(v.isDirectory==true || v.isRegularFile==true) { throw ArchiveError.unsafePath(file.path) }
            if v.isRegularFile==true {
                let attributes=try fm.attributesOfItem(atPath:file.path)
                if (attributes[.referenceCount] as? NSNumber)?.intValue ?? 1 > 1 { throw ArchiveError.unsafePath("Hard link: "+file.path) }
                let size=UInt64(max(0,v.fileSize ?? 0)),sum=bytes.addingReportingOverflow(size)
                guard !sum.overflow,sum.partialValue<=limits.maxExpandedBytes else { throw ArchiveError.resourceLimit("Expanded byte limit exceeded.") }
                bytes=sum.partialValue
                // Remove setuid/setgid/sticky bits and world-write permission.
                if let mode=attributes[.posixPermissions] as? NSNumber {
                    try fm.setAttributes([.posixPermissions:mode.intValue & 0o755],ofItemAtPath:file.path)
                }
            }
            if let source=quarantineSource {
                let result=source.path.withCString { s in file.path.withCString { arc_copy_quarantine(s,$0) } }
                if result != 0 { throw ArchiveError.io("Could not preserve macOS quarantine metadata.") }
            }
        }
        if let e=walkError { throw ArchiveError.io(e.localizedDescription) }
        return (count,bytes)
    }
    public static func requireFreeSpace(at parent:URL,bytes:UInt64) throws {
        if let free=(try FileManager.default.attributesOfFileSystem(forPath:parent.path)[.systemFreeSize] as? NSNumber)?.uint64Value {
            let overhead:UInt64=64*1024*1024
            guard free>overhead,bytes<=free-overhead else { throw ArchiveError.resourceLimit("Not enough free disk space for the expanded files.") }
        }
    }
}

public final class Workspace {
    public let root:URL
    public let payload:URL
    public let scratch:URL
    private let fm=FileManager.default
    public init(parent:URL) throws {
        var isDir:ObjCBool=false
        guard fm.fileExists(atPath:parent.path,isDirectory:&isDir),isDir.boolValue else { throw ArchiveError.invalid("Choose an existing output folder.") }
        root=try PathSafety.physicalURL(parent).appendingPathComponent(".arcora-"+UUID().uuidString,isDirectory:true)
        payload=root.appendingPathComponent("payload",isDirectory:true)
        scratch=root.appendingPathComponent("scratch",isDirectory:true)
        do {
            try fm.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            try fm.createDirectory(at:payload,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            try fm.createDirectory(at:scratch,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            try Data("Arcora workspace v1\n".utf8).write(to:root.appendingPathComponent(".owner"),options:.atomic)
        } catch { try? fm.removeItem(at:root); throw error }
    }
    public func commit(_ item:URL,to proposed:URL,policy:CollisionPolicy) throws -> URL {
        guard PathSafety.contains(root,item),item != root else { throw ArchiveError.invalid("Commit source is not inside the workspace.") }
        for index in 0..<10000 {
            var destination=proposed
            if index>0 {
                guard policy == .rename else { throw ArchiveError.collision(proposed.lastPathComponent) }
                let name=proposed.lastPathComponent
                // Keep compound archive suffixes intact.
                let suffix=[".tar.gz",".tar.bz2",".tar.xz"].first(where:{name.lowercased().hasSuffix($0)})
                    ?? (proposed.pathExtension.isEmpty ? "" : "."+proposed.pathExtension)
                let stem=String(name.dropLast(suffix.count))
                destination=proposed.deletingLastPathComponent().appendingPathComponent("\(stem) (\(index+1))\(suffix)")
            }
            let result=item.path.withCString { s in destination.path.withCString { arc_rename_exclusive(s,$0) } }
            if result==0 { return destination }
            if errno != EEXIST && errno != ENOTEMPTY { throw ArchiveError.io(String(cString:strerror(errno))) }
        }
        throw ArchiveError.collision(proposed.lastPathComponent)
    }
    deinit { try? fm.removeItem(at:root) }
}
