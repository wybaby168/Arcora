import Foundation

public enum ArchiveError: Error, LocalizedError, Equatable {
    case invalid(String), unsafePath(String), unsupported(String), missingEngine(String)
    case passwordRequired, wrongPassword, cancelled, timedOut
    case missingVolume(String), collision(String), resourceLimit(String)
    case engine(Int32, String), io(String)
    case licenseRequired(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let s), .unsafePath(let s), .unsupported(let s), .missingEngine(let s),
             .missingVolume(let s), .collision(let s), .resourceLimit(let s), .io(let s), .licenseRequired(let s): return s
        case .passwordRequired: return "A password is required."
        case .wrongPassword: return "The password is incorrect, or the encrypted data is damaged."
        case .cancelled: return "The operation was cancelled."
        case .timedOut: return "The operation exceeded its time limit."
        case .engine(let code, let detail): return "Engine exit \(code): \(detail)"
        }
    }
    public var localizationKey: String {
        switch self {
        case .invalid: return "error.invalid"
        case .unsafePath: return "error.unsafe"
        case .unsupported: return "error.unsupported"
        case .missingEngine: return "error.engine"
        case .passwordRequired: return "error.passwordRequired"
        case .wrongPassword: return "error.wrongPassword"
        case .cancelled: return "state.cancelled"
        case .timedOut: return "error.timeout"
        case .missingVolume: return "error.volume"
        case .collision: return "error.collision"
        case .resourceLimit: return "error.limit"
        case .engine: return "error.operation"
        case .io: return "error.io"
        case .licenseRequired:return "error.rarLicense"
        }
    }
}

public enum ArchiveFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case sevenZip="7z", zip, rar, tar, tarGzip="tar.gz", tarBzip2="tar.bz2", tarXz="tar.xz", gzip="gz", bzip2="bz2", xz
    public var id: String { rawValue }
    public var title: String { rawValue.uppercased() }
    public var levels:[Int] { self == .tar ? [0] : supportsPassword ? [0,1,3,5,7,9] : [1,3,5,7,9] }
    public var supportsPassword: Bool { [.sevenZip,.zip,.rar].contains(self) }
    public var supportsVolumes: Bool { [.sevenZip,.zip,.rar].contains(self) }
    public var supportsDictionary: Bool { [.sevenZip,.rar,.xz,.tarXz].contains(self) }
    public var supportsSolid: Bool { self == .sevenZip || self == .rar }
    public var singleStream: Bool { [.gzip,.bzip2,.xz].contains(self) }
    public var wrappedTar: Bool { [.tarGzip,.tarBzip2,.tarXz].contains(self) }
    public var sevenZipType: String {
        switch self { case .sevenZip:return "7z"; case .tarGzip,.gzip:return "gzip"
        case .tarBzip2,.bzip2:return "bzip2"; case .tarXz,.xz:return "xz"
        default:return rawValue }
    }
}
public enum ZIPEncryption: String, CaseIterable, Codable, Sendable { case aes256="AES256", zipCrypto="ZipCrypto" }
public enum CollisionPolicy: String, CaseIterable, Codable, Sendable { case rename, fail }
public enum ArchiveBackend: String, Codable, Sendable { case sevenZip, libarchive }

public struct CompressionOptions: Codable, Sendable, Equatable {
    public var format: ArchiveFormat = .sevenZip
    public var level: Int = 5
    public var dictionaryMiB: Int = 32
    public var threads: Int = max(1,min(8,ProcessInfo.processInfo.activeProcessorCount))
    public var volumeBytes: UInt64? = nil
    public var solid: Bool = true
    public var encryptHeaders: Bool = true
    public var zipEncryption: ZIPEncryption = .aes256
    public var verifyAfterCreation: Bool = true
    public init() {}
    public func validate(hasPassword: Bool) throws {
        guard format.levels.contains(level) else { throw ArchiveError.invalid("Compression level is not available for this format.") }
        guard (1...256).contains(threads) else { throw ArchiveError.invalid("Thread count must be 1…256.") }
        guard [1,2,4,8,16,32,64,128,256,512,1024].contains(dictionaryMiB) else { throw ArchiveError.invalid("Unsupported dictionary size.") }
        if hasPassword && !format.supportsPassword { throw ArchiveError.invalid("This format cannot store an encrypted archive.") }
        if let bytes=volumeBytes {
            guard format.supportsVolumes && bytes>=65536 && bytes<=UInt64(Int64.max) else {
                throw ArchiveError.invalid("Volumes require 7z, ZIP or RAR and a size of at least 64 KiB.")
            }
        }
    }
    // Conservative scheduling estimate, not an operating-system RSS hard limit.
    public var estimatedMemoryBytes: UInt64 {
        let mib:UInt64=1024*1024
        if level==0 { return 64*mib }
        switch format {
        case .sevenZip,.xz,.tarXz:
            return UInt64(dictionaryMiB)*mib*12*UInt64(max(1,(threads+1)/2))+128*mib
        case .rar: return UInt64(dictionaryMiB)*mib*8+UInt64(threads)*64*mib
        case .zip: return UInt64(threads)*32*mib+64*mib
        case .bzip2,.tarBzip2: return UInt64(threads)*16*mib+64*mib
        default: return 128*mib
        }
    }
}

public struct SafetyLimits: Codable, Sendable {
    public var maxExpandedBytes: UInt64 = 200*1024*1024*1024
    public var maxEntries: Int = 250_000
    public var maxListingBytes: Int = 64*1024*1024
    public var maxMemoryBytes: UInt64 = max(256*1024*1024, ProcessInfo.processInfo.physicalMemory/2)
    public var timeout: TimeInterval = 24*60*60
    public init() {}
}
public struct ArchiveEntry: Codable, Sendable, Identifiable, Equatable {
    public var path: String
    public var size: UInt64
    public var packedSize: UInt64?
    public var modified: Date?
    public var isDirectory: Bool
    public var isEncrypted: Bool
    public var isUnsafeType: Bool
    public var linkTarget: String?
    public var id: String { path }
    public init(path:String,size:UInt64=0,packedSize:UInt64?=nil,modified:Date?=nil,
                isDirectory:Bool=false,isEncrypted:Bool=false,isUnsafeType:Bool=false,linkTarget:String?=nil) {
        self.path=path; self.size=size; self.packedSize=packedSize; self.modified=modified
        self.isDirectory=isDirectory; self.isEncrypted=isEncrypted; self.isUnsafeType=isUnsafeType; self.linkTarget=linkTarget
    }
}
public struct ArchiveManifest: Codable, Sendable {
    public var source: URL
    public var backend: ArchiveBackend
    public var entries: [ArchiveEntry]
    public var format: String
    public var totalBytes: UInt64 { entries.reduce(0) { n,e in n.addingReportingOverflow(e.size).overflow ? UInt64.max : n+e.size } }
    public var encrypted: Bool { entries.contains { $0.isEncrypted } }
    public init(source:URL,backend:ArchiveBackend,entries:[ArchiveEntry],format:String) {
        self.source=source; self.backend=backend; self.entries=entries; self.format=format
    }
}
public struct ProgressEvent: Codable, Sendable {
    public var phase: String
    public var fraction: Double?
    public var bytes: UInt64?
    public var entries: UInt64?
    public var detail: String?
    public init(_ phase:String,fraction:Double?=nil,bytes:UInt64?=nil,entries:UInt64?=nil,detail:String?=nil) {
        self.phase=phase; self.fraction=fraction; self.bytes=bytes; self.entries=entries; self.detail=detail
    }
}
public typealias ProgressSink = @Sendable (ProgressEvent) -> Void
public struct OperationResult: Sendable {
    public var outputs:[URL]
    public var entries:Int
    public var bytes:UInt64
    public init(outputs:[URL],entries:Int=0,bytes:UInt64=0) { self.outputs=outputs; self.entries=entries; self.bytes=bytes }
}
