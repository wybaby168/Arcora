import Foundation
import CArcora
#if os(macOS)
import Darwin
#else
import Glibc
#endif

public struct EngineCommand: Sendable {
    public var executable:URL
    public var arguments:[String]
    public var directory:URL?
    public var secret:Secret?
    public var passwordCopies:Int
    public var rarConfigurationDirectory:URL?
    public var redactRARRegistration:Bool
    public init(_ executable:URL,_ arguments:[String],directory:URL?=nil,secret:Secret?=nil,passwordCopies:Int=2,
                rarConfigurationDirectory:URL?=nil,redactRARRegistration:Bool=false) {
        self.executable=executable; self.arguments=arguments; self.directory=directory
        self.secret=secret; self.passwordCopies=passwordCopies
        self.rarConfigurationDirectory=rarConfigurationDirectory;self.redactRARRegistration=redactRARRegistration
    }
}
public final class JobControl: @unchecked Sendable {
    private let lock=NSLock()
    private var current:Process?
    private var cancelled=false
    private var paused=false
    private var pauseStart:Date?
    private var pauseSeconds:TimeInterval=0
    public init() {}
    public var isCancelled:Bool { lock.lock(); defer{lock.unlock()}; return cancelled }
    public var isPaused:Bool { lock.lock(); defer{lock.unlock()}; return paused }
    public var pausedDuration:TimeInterval {
        lock.lock(); defer{lock.unlock()}; return pauseSeconds+(pauseStart.map{Date().timeIntervalSince($0)} ?? 0)
    }
    public func check() throws { if isCancelled { throw ArchiveError.cancelled } }
    public func waitWhilePaused() throws {
        while isPaused { try check(); Thread.sleep(forTimeInterval:0.05) }
        try check()
    }
    func register(_ process:Process) throws {
        lock.lock()
        current=process
        let stop=paused, cancel=cancelled
        lock.unlock()
        if cancel { terminate(process); throw ArchiveError.cancelled }
        if stop && process.isRunning { _=kill(process.processIdentifier,SIGSTOP) }
    }
    func unregister(_ process:Process) {
        lock.lock(); if current === process { current=nil }; lock.unlock()
    }
    public func pause() {
        lock.lock()
        guard !paused && !cancelled else { lock.unlock(); return }
        paused=true; pauseStart=Date(); let p=current
        if let p,p.isRunning { _=kill(p.processIdentifier,SIGSTOP) }
        lock.unlock()
    }
    public func resume() {
        lock.lock()
        guard paused else { lock.unlock(); return }
        paused=false
        if let start=pauseStart { pauseSeconds+=Date().timeIntervalSince(start) }; pauseStart=nil
        if let p=current,p.isRunning { _=kill(p.processIdentifier,SIGCONT) }
        lock.unlock()
    }
    public func cancel() {
        lock.lock(); cancelled=true; let p=current; lock.unlock()
        if let p { terminate(p) }
    }
    private func terminate(_ p:Process) {
        guard p.isRunning else { return }
        _=kill(p.processIdentifier,SIGCONT)
        p.terminate()
        // Hold the Process object, not an unowned/reusable PID, until reaped.
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+2) {
            if p.isRunning { _=kill(p.processIdentifier,SIGKILL) }
        }
    }
}
public struct ProcessResult: Sendable {
    public var status:Int32
    public var output:String
    public var diagnostics:String
    public init(status:Int32,output:String,diagnostics:String="") {
        self.status=status;self.output=output;self.diagnostics=diagnostics
    }
}

public final class ProcessRunner: @unchecked Sendable {
    public init() { arc_ignore_sigpipe() }
    /// Blocking by design: run on a background thread, never on the AppKit main thread.
    /// Drain both streams independently so a large listing cannot displace an engine error.
    public func run(_ command:EngineCommand,control:JobControl=JobControl(),timeout:TimeInterval=86400,
                    outputLimit:Int=1_048_576,captureAll:Bool=false,
                    onData:((Data)->Void)?=nil) throws -> ProcessResult {
        try control.waitWhilePaused()
        guard command.executable.isFileURL, FileManager.default.isExecutableFile(atPath:command.executable.path) else {
            throw ArchiveError.missingEngine(command.executable.path)
        }
        guard outputLimit>0 else {throw ArchiveError.invalid("The process output limit must be positive.")}
        let process=Process(), output=Pipe(),errors=Pipe()
        process.executableURL=command.executable
        process.arguments=command.arguments
        process.currentDirectoryURL=command.directory
        // Do not inherit 7z/RAR configuration or injected DYLD/LD library settings.
        var env=["PATH":"/usr/bin:/bin:/usr/sbin:/sbin", "LANG":"en_US.UTF-8", "LC_ALL":"en_US.UTF-8"]
        if let home=ProcessInfo.processInfo.environment["HOME"] { env["HOME"]=home }
        if let configuration=command.rarConfigurationDirectory {env["XDG_CONFIG_HOME"]=configuration.path}
        #if os(Linux)
        env["LANG"]="C.UTF-8"; env["LC_ALL"]="C.UTF-8"
        #endif
        process.environment=env
        process.standardOutput=output; process.standardError=errors
        let input:Pipe?=command.secret == nil ? nil : Pipe()
        if let input { process.standardInput=input } else { process.standardInput=FileHandle.nullDevice }
        do { try process.run() } catch { throw ArchiveError.io(error.localizedDescription) }
        // Close the parent's write end; otherwise EOF may never reach the reader.
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        let diagnostics=DiagnosticCapture(limit:min(outputLimit,1_048_576)),drained=DispatchGroup()
        drained.enter()
        DispatchQueue.global(qos:.utility).async {
            defer {drained.leave()}
            diagnostics.read(errors.fileHandleForReading)
        }
        defer { control.unregister(process); try? output.fileHandleForReading.close() }
        do { try control.register(process) } catch {
            process.waitUntilExit(); drained.wait(); throw error
        }
        let begin=Date(), pausedBefore=control.pausedDuration
        let watchdog=DispatchSource.makeTimerSource(queue:.global(qos:.utility))
        let timedOut=LockedFlag()
        watchdog.schedule(deadline:.now()+1,repeating:1)
        watchdog.setEventHandler {
            if Date().timeIntervalSince(begin)-(control.pausedDuration-pausedBefore)>timeout && process.isRunning {
                timedOut.set(); control.cancel()
            }
        }
        watchdog.resume()
        defer { watchdog.cancel() }
        if let input,let secret=command.secret {
            try? input.fileHandleForReading.close()
            DispatchQueue.global(qos:.utility).async {
                var bytes=secret.withBytes { $0 }
                var message=Data()
                for _ in 0..<max(1,min(2,command.passwordCopies)) { message.append(bytes); message.append(10) }
                defer {
                    bytes.withUnsafeMutableBytes { if let p=$0.baseAddress { arc_zero(p,$0.count) } }
                    message.withUnsafeMutableBytes { if let p=$0.baseAddress { arc_zero(p,$0.count) } }
                    try? input.fileHandleForWriting.close()
                }
                try? input.fileHandleForWriting.write(contentsOf:message)
            }
        }
        var captured=Data(), exceeded=false
        do {
            while let chunk=try output.fileHandleForReading.read(upToCount:65536),!chunk.isEmpty {
                onData?(chunk)
                captured.append(chunk)
                if captured.count>outputLimit {
                    if captureAll { exceeded=true; control.cancel(); break }
                    captured.removeFirst(captured.count-outputLimit)
                }
            }
        } catch {
            control.cancel(); process.waitUntilExit(); drained.wait(); throw ArchiveError.io(error.localizedDescription)
        }
        process.waitUntilExit()
        drained.wait()
        if let failure=diagnostics.failure {throw ArchiveError.io(failure)}
        if exceeded { throw ArchiveError.resourceLimit("The archive listing exceeds the configured memory limit.") }
        if timedOut.value { throw ArchiveError.timedOut }
        try control.check()
        func redacted(_ data:Data,includeSecret:Bool)->String {
            var text=String(decoding:data,as:UTF8.self)
            if command.redactRARRegistration {text=text.replacingOccurrences(of:"(?m)^Registered to[^\\r\\n]*",with:"Registered to <private>",options:.regularExpression)}
            if includeSecret,let secret=command.secret {
                secret.withBytes { bytes in
                    if !bytes.isEmpty {text=text.replacingOccurrences(of:String(decoding:bytes,as:UTF8.self),with:"<redacted>")}
                }
            }
            return text
        }
        if (!captureAll || process.terminationStatus != 0),!diagnostics.data.isEmpty {
            captured.append(10);captured.append(diagnostics.data)
            if !captureAll,captured.count>outputLimit {captured.removeFirst(captured.count-outputLimit)}
        }
        // Successful structured listings preserve names even if a name contains the password.
        return ProcessResult(status:process.terminationStatus,
            output:redacted(captured,includeSecret:process.terminationStatus != 0 || !captureAll),
            diagnostics:redacted(diagnostics.data,includeSecret:true))
    }
    public static func requireSuccess(_ result:ProcessResult,passwordSupplied:Bool) throws {
        guard result.status==0 else {
            let report=result.diagnostics+"\n"+result.output
            let lower=report.lowercased()
            if lower.contains("wrong password") || lower.contains("incorrect password") {
                throw passwordSupplied ? ArchiveError.wrongPassword : ArchiveError.passwordRequired
            }
            if lower.contains("password required") || lower.contains("passphrase required") || (!passwordSupplied && lower.contains("enter password")) {
                throw passwordSupplied ? ArchiveError.wrongPassword : ArchiveError.passwordRequired
            }
            if lower.contains("missing volume") || lower.contains("cannot find volume") {
                let expression=try NSRegularExpression(pattern:"(?im)(?:missing volume|cannot find volume)[\\t ]*:?[\\t ]*([^\\r\\n]+)")
                if let match=expression.firstMatch(in:report,range:NSRange(report.startIndex...,in:report)),
                   let range=Range(match.range(at:1),in:report) {
                    let path=String(report[range]).trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"\""))
                    throw ArchiveError.missingVolume((path as NSString).lastPathComponent)
                }
                throw ArchiveError.missingVolume("")
            }
            if lower.contains("unexpected end of archive") || lower.contains("unexpected end of data") {
                throw ArchiveError.incompleteArchive
            }
            // Exit 1 (warning / skipped source) is NOT a successful complete archive.
            let detail=result.diagnostics.isEmpty ? result.output : result.diagnostics
            throw ArchiveError.engine(result.status,String(detail.suffix(1_048_576)))
        }
    }
}
/// One reader owns this buffer. The caller reads it only after the dispatch group joins.
private final class DiagnosticCapture:@unchecked Sendable {
    private let limit:Int
    private(set) var data=Data()
    private(set) var failure:String?
    init(limit:Int) {self.limit=limit}
    func read(_ handle:FileHandle) {
        defer {try? handle.close()}
        do {
            while let chunk=try handle.read(upToCount:65536),!chunk.isEmpty {
                data.append(chunk)
                if data.count>limit {data.removeFirst(data.count-limit)}
            }
        } catch {failure=error.localizedDescription}
    }
}
private final class LockedFlag: @unchecked Sendable {
    private let lock=NSLock(); private var flag=false
    func set() { lock.lock(); flag=true; lock.unlock() }
    var value:Bool { lock.lock(); defer{lock.unlock()}; return flag }
}

/// Decode complete UTF-8 lines, preserving multibyte characters split across pipe reads.
public final class LineFramer {
    private var pending=Data()
    private let limit:Int
    public init(limit:Int=131072) { self.limit=limit }
    public func consume(_ data:Data,_ body:(String)->Void) {
        pending.append(data)
        while let index=pending.firstIndex(where:{$0==10 || $0==13 || $0==8}) {
            let line=pending.prefix(upTo:index)
            if !line.isEmpty { body(String(decoding:line,as:UTF8.self)) }
            pending.removeSubrange(...index)
        }
        if pending.count>limit { pending.removeFirst(pending.count-limit) }
    }
    public func finish(_ body:(String)->Void) {
        if !pending.isEmpty { body(String(decoding:pending,as:UTF8.self)); pending.removeAll() }
    }
}
