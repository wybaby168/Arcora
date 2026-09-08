import Foundation
import CArcora

/// Never Codable, never printed, never appended to argv or the environment.
/// The UI's SecureField and Swift/Foundation may hold copies; zeroization is best effort,
/// not a claim that a managed-language password never appears in process memory.
public final class Secret: @unchecked Sendable, CustomStringConvertible {
    private let lock=NSLock()
    private var bytes:Data
    public var description:String { "<redacted>" }
    public init(_ value:String) throws {
        guard !value.isEmpty, value.utf8.count<=1024,
              !value.unicodeScalars.contains(where: { $0.value<32 || $0.value==127 }) else {
            throw ArchiveError.invalid("Passwords must be 1…1024 UTF-8 bytes and contain no control characters.")
        }
        bytes=Data(value.utf8)
    }
    private init(data:Data) { bytes=data }
    public func copy() -> Secret { lock.lock(); defer { lock.unlock() }; return Secret(data:bytes) }
    public func withBytes<T>(_ body:(Data)throws->T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body(bytes)
    }
    public func withCString<T>(_ body:(UnsafePointer<CChar>)throws->T) rethrows -> T {
        try withBytes { value in
            var terminated=value; terminated.append(0)
            defer { terminated.withUnsafeMutableBytes { if let p=$0.baseAddress { arc_zero(p,$0.count) } } }
            return try terminated.withUnsafeBytes { try body($0.bindMemory(to:CChar.self).baseAddress!) }
        }
    }
    public func clear() {
        lock.lock(); defer { lock.unlock() }
        bytes.withUnsafeMutableBytes { if let p=$0.baseAddress { arc_zero(p,$0.count) } }
        bytes.removeAll(keepingCapacity:false)
    }
    deinit { clear() }
}
