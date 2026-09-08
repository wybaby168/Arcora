#if os(macOS)
import Foundation
import CryptoKit
import Darwin
import CArcora

/// Metadata only: Arcora never downloads or redistributes these RAR packages.
/// Update both these pins and Vendor/engines.lock.json after reviewing a new upstream release.
public struct RARPackage: Codable, Equatable, Sendable {
    public let architecture:String
    public let version:String
    public let filename:String
    public let downloadURL:URL
    public let sha256:String
    public let binarySha256:String

    public static let arm64=RARPackage(architecture:"arm64",version:"7.23",filename:"rarmacos-arm-723.tar.gz",
        downloadURL:URL(string:"https://www.rarlab.com/rar/rarmacos-arm-723.tar.gz")!,
        sha256:"68b393c000758d477fde43c955ff7542f12f76f3f5e87cdda923152fc791bd4d",
        binarySha256:"fd6c7db73c659a28b50408354f4a4845c53a67f929f37fd99df92aa77b9f5153")
    public static let x86_64=RARPackage(architecture:"x86_64",version:"7.23",filename:"rarmacos-x64-723.tar.gz",
        downloadURL:URL(string:"https://www.rarlab.com/rar/rarmacos-x64-723.tar.gz")!,
        sha256:"da1fb3c3d7748136c9b369b683d574b372cb1ed049a634a81f85d93918346d8f",
        binarySha256:"2512979417b2ba1c60f1a5783051931928099c3f407be8a12ef030c9cb54a8fb")
    public static var current:RARPackage {
        // Prefer native ARM on Apple Silicon, including when Arcora runs under Rosetta.
        var arm:Int32=0,size=MemoryLayout<Int32>.size
        let supported=sysctlbyname("hw.optional.arm64",&arm,&size,nil,0)==0 && arm==1
        return forHardware(arm64:supported)
    }
    static func forHardware(arm64:Bool)->RARPackage {arm64 ? .arm64 : .x86_64}
}

/// Installs only a user-selected, hash-pinned, complete official package into the user's profile.
/// No installer scripts, shell, admin rights, network requests or quarantine removal are used.
public struct RARInstallationStore:Sendable {
    public let root:URL
    public let package:RARPackage
    public var installation:URL {root.appendingPathComponent("current",isDirectory:true)}
    public var originalPackage:URL {installation.appendingPathComponent(package.filename)}
    public var executable:URL {installation.appendingPathComponent("rar/rar")}
    private var fm:FileManager {FileManager.default}
    public init(root:URL?=nil,package:RARPackage = .current) {
        self.root=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("Arcora/RAREngine",isDirectory:true)
        self.package=package
    }
    private static func digest(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    private func read(_ url:URL,limit:Int=16*1024*1024)throws->Data {
        let attrs=try fm.attributesOfItem(atPath:url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.referenceCount] as? NSNumber)?.intValue == 1,
              let size=attrs[.size] as? NSNumber,size.intValue>0,size.intValue<=limit else {
            throw ArchiveError.invalid("Select the unchanged official RAR .tar.gz package (maximum 16 MiB); links and special files are not accepted.")
        }
        // O_NOFOLLOW also rejects a symlink substituted after the metadata check.
        let descriptor=open(url.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
        guard descriptor>=0 else {throw ArchiveError.unsafePath(url.path)}
        let handle=FileHandle(fileDescriptor:descriptor,closeOnDealloc:true)
        defer {try? handle.close()}
        var data=Data()
        while let chunk=try handle.read(upToCount:65_536),!chunk.isEmpty {
            data.append(chunk)
            guard data.count<=limit else {throw ArchiveError.resourceLimit("RAR package exceeds the import limit.")}
        }
        return data
    }
    private func checkDirectories()throws {
        for url in [root,installation,installation.appendingPathComponent("rar")] {
            if let attrs=try? fm.attributesOfItem(atPath:url.path) {
                guard attrs[.type] as? FileAttributeType == .typeDirectory else {throw ArchiveError.unsafePath(url.path)}
            }
        }
    }
    public func installedExecutable()throws->URL? {
        try checkDirectories()
        guard fm.fileExists(atPath:installation.path) else {return nil}
        let receipt=try JSONDecoder().decode(RARPackage.self,from:read(installation.appendingPathComponent("arcora-package.json"),limit:8192))
        guard receipt==package,Self.digest(try read(originalPackage))==package.sha256,
              Self.digest(try read(executable))==package.binarySha256,fm.isExecutableFile(atPath:executable.path) else {
            throw ArchiveError.invalid("The imported RAR engine is damaged or incompatible. Import the matching official original package again in Settings.")
        }
        return executable
    }
    public func importPackage(from source:URL,control:JobControl=JobControl())throws {
        try control.check();try checkDirectories()
        let data=try read(source)
        let digest=Self.digest(data)
        guard digest==package.sha256 else {
            let other=package.architecture=="arm64" ? RARPackage.x86_64 : .arm64
            if digest==other.sha256 {throw ArchiveError.invalid("Wrong architecture. Download \(package.filename) for this Mac.")}
            throw ArchiveError.invalid("RAR package verification failed. Select the complete, unchanged \(package.filename) downloaded from rarlab.com. Other versions are not accepted by this Arcora release.")
        }
        try control.check()
        try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let stage=root.appendingPathComponent(".import-"+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer {try? fm.removeItem(at:stage)}
        let original=stage.appendingPathComponent(package.filename)
        try data.write(to:original,options:.withoutOverwriting)
        try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:original.path)
        let quarantine=source.path.withCString{s in original.path.withCString{arc_copy_quarantine(s,$0)}}
        guard quarantine==0 else {throw ArchiveError.io("Could not preserve macOS quarantine metadata.")}
        var limits=SafetyLimits();limits.maxEntries=128;limits.maxExpandedBytes=16*1024*1024
        let entries=try NativeArchive.list(original,limits:limits,control:control)
        try PathSafety.validate(entries,limits:limits)
        guard !entries.isEmpty,try entries.allSatisfy({item in
            let path=try PathSafety.canonicalEntry(item.path)
            return path=="rar" && item.isDirectory || path.hasPrefix("rar/")
        }) else {throw ArchiveError.unsafePath("Unexpected contents in official RAR package.")}
        try NativeArchive.read(original,to:stage,limits:limits,control:control)
        _=try PathSafety.auditOutput(stage,limits:limits,quarantineSource:original,control:control)
        let binary=stage.appendingPathComponent("rar/rar")
        guard Self.digest(try read(binary))==package.binarySha256 else {throw ArchiveError.invalid("RAR executable verification failed.")}
        for name in ["rar","unrar","default.sfx"] {
            let path=stage.appendingPathComponent("rar/"+name)
            if fm.fileExists(atPath:path.path) {try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:path.path)}
        }
        try JSONEncoder().encode(package).write(to:stage.appendingPathComponent("arcora-package.json"),options:.withoutOverwriting)
        try control.check();try checkDirectories()
        // Commit only after all validation. Failed/cancelled imports preserve the current installation.
        if fm.fileExists(atPath:installation.path) {
            _=try fm.replaceItemAt(installation,withItemAt:stage)
        } else {try fm.moveItem(at:stage,to:installation)}
    }
    public func moveImportedCopyToTrash()throws {
        try checkDirectories()
        guard fm.fileExists(atPath:installation.path) else {return}
        _=try fm.trashItem(at:installation,resultingItemURL:nil)
    }
}
#endif
