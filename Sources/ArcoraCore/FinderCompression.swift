import Foundation

public enum FinderCompressionAction:String,CaseIterable,Sendable {
    case zip, sevenZip="7z", rar, custom
    public var format:ArchiveFormat? {
        switch self {case .zip:return .zip;case .sevenZip:return .sevenZip;case .rar:return .rar;case .custom:return nil}
    }
}

/// A file-selection snapshot, never shell text or a URL to download.
public struct FinderCompressionRequest:Sendable {
    public let files:[URL]
    public let action:FinderCompressionAction
    public init(files:[URL],action:FinderCompressionAction)throws {
        guard !files.isEmpty,files.count<=10_000 else {throw ArchiveError.invalid("Select between 1 and 10,000 files or folders.")}
        guard files.allSatisfy({$0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost")}) else {
            throw ArchiveError.invalid("Finder compression accepts local file URLs only.")
        }
        var seen=Set<String>()
        self.files=try files.map { url in
            try PathSafety.safeListPath(url.path)
            return url.standardizedFileURL
        }.filter {seen.insert($0.path).inserted}
        self.action=action
    }
}

public struct FinderCompressionPlan:Sendable {
    public let files:[URL]
    /// Nil for selections from multiple locations. Let the user choose instead
    /// of silently publishing to a surprising common ancestor or the disk root.
    public let siblingDirectory:URL?
    public let name:String

    public init(request:FinderCompressionRequest,fallbackName:String="Archive")throws {
        var unique=[URL](),directories=Set<String>()
        for input in request.files {
            let values=try input.resourceValues(forKeys:[.isDirectoryKey,.isRegularFileKey,.isSymbolicLinkKey])
            guard values.isSymbolicLink != true,values.isDirectory==true || values.isRegularFile==true else {
                throw ArchiveError.unsafePath(input.path)
            }
            let url=try PathSafety.physicalURL(input.deletingLastPathComponent()).appendingPathComponent(input.lastPathComponent)
            if !unique.contains(url) {unique.append(url)}
            if values.isDirectory==true {directories.insert(url.path)}
        }
        // A folder and one of its children selected together should be archived once.
        files=unique.filter { child in !unique.contains { parent in
            parent != child && directories.contains(parent.path) && PathSafety.contains(parent,child)
        }}
        let parents=Set(files.map{$0.deletingLastPathComponent()})
        siblingDirectory=parents.count==1 ? parents.first : nil
        let candidate:String
        if files.count==1,let file=files.first {
            candidate=directories.contains(file.path) ? file.lastPathComponent : file.deletingPathExtension().lastPathComponent
        } else {candidate=siblingDirectory?.lastPathComponent ?? fallbackName}
        // Long source names are valid inputs even when they cannot be output basenames.
        name=(try? PathSafety.safeFilename(candidate)) != nil ? candidate : fallbackName
        try PathSafety.safeFilename(name)
    }

    public static func quickOptions(format:ArchiveFormat,threads:Int)->CompressionOptions {
        var options=CompressionOptions()
        options.format=format;options.threads=max(1,min(4,threads));options.dictionaryMiB=16
        options.verifyAfterCreation=true
        return options
    }
}

#if os(macOS)
import AppKit

/// Snapshot the pasteboard before returning to Services. Finder may reuse it
/// immediately. Requests received before the window is ready are not discarded.
@MainActor
public final class FinderServicesProvider:NSObject {
    public var handler:((FinderCompressionRequest)->Void)? {didSet {drain()}}
    private var pending=[FinderCompressionRequest]()
    public override init() {super.init()}
    private func drain() {
        guard let handler else {return}
        let requests=pending;pending.removeAll()
        for request in requests {handler(request)}
    }
    public static func files(from pasteboard:NSPasteboard)throws->[URL] {
        let legacy=NSPasteboard.PasteboardType("NSFilenamesPboardType")
        // Legacy Finder clients may publish multiple paths under one pasteboard item.
        if let paths=pasteboard.propertyList(forType:legacy) as? [String],!paths.isEmpty {
            guard paths.allSatisfy({$0.hasPrefix("/")}) else {throw ArchiveError.invalid("File paths must be absolute.")}
            return paths.map{URL(fileURLWithPath:$0)}
        }
        let urls=pasteboard.readObjects(forClasses:[NSURL.self],options:[:]) as? [URL] ?? []
        guard !urls.isEmpty else {throw ArchiveError.invalid("No file selection was received from Finder.")}
        return urls
    }
    @objc public func compressFiles(_ pasteboard:NSPasteboard,userData:String?,error errorPointer:AutoreleasingUnsafeMutablePointer<NSString?>) {
        do {
            guard let action=FinderCompressionAction(rawValue:userData ?? "custom") else {throw ArchiveError.invalid("Unknown Finder compression action.")}
            guard pending.count<32 else {throw ArchiveError.resourceLimit("Too many pending Finder requests.")}
            let request=try FinderCompressionRequest(files:Self.files(from:pasteboard),action:action)
            pending.append(request);drain()
        } catch {
            // Services may log this string. Do not include selected paths or secrets.
            errorPointer.pointee=Bundle.main.localizedString(forKey:"Arcora could not accept this file selection. Open Arcora and try again.",value:nil,table:"ServicesMenu") as NSString
        }
    }
}
#endif
