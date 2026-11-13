import Foundation
#if os(macOS)
import Darwin
#else
import Glibc
#endif

extension ArchiveService {
    public func split(_ input:URL,to parent:URL,name:String?=nil,partBytes:UInt64,
                      collision:CollisionPolicy = .rename,control:JobControl=JobControl(),progress:ProgressSink?=nil) throws -> OperationResult {
        try control.waitWhilePaused()
        try PathSafety.safeListPath(input.path)
        guard partBytes>=65536,partBytes<=UInt64(Int64.max) else {throw ArchiveError.invalid("The part size must be at least 64 KiB.")}
        let volumes=try VolumeResolver.resolve(input)
        guard !volumes.isMultipart else {throw ArchiveError.invalid("Select a single complete archive to split.")}
        let basename=name ?? input.lastPathComponent
        try PathSafety.safeFilename(basename)
        try PathSafety.safeFilename(basename+".parts")
        let descriptor=open(input.path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
        guard descriptor>=0 else {throw ArchiveError.io(String(cString:strerror(errno)))}
        let reader=FileHandle(fileDescriptor:descriptor,closeOnDealloc:true)
        defer {try? reader.close()}
        var original=stat()
        guard fstat(descriptor,&original)==0,original.st_mode & mode_t(S_IFMT)==mode_t(S_IFREG),original.st_size>0 else {
            throw ArchiveError.invalid("Select a nonempty regular file to split.")
        }
        let size=UInt64(original.st_size),partCount=(size-1)/partBytes+1
        guard size<=limits.maxExpandedBytes,limits.maxEntries>0,partCount<=UInt64(limits.maxEntries) else {
            throw ArchiveError.resourceLimit("The split archive exceeds the configured output limits.")
        }
        try PathSafety.safeFilename(basename+String(format:".%03llu",partCount))
        try PathSafety.requireFreeSpace(at:parent,bytes:size)
        let area=try Workspace(parent:parent)
        var written:UInt64=0,lastProgress=Date.distantPast
        for index in 1...Int(partCount) {
            try control.waitWhilePaused()
            let filename=basename+String(format:".%03llu",UInt64(index))
            try PathSafety.safeFilename(filename)
            let output=area.payload.appendingPathComponent(filename)
            let file=open(output.path,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW|O_CLOEXEC,mode_t(0o600))
            guard file>=0 else {throw ArchiveError.io(String(cString:strerror(errno)))}
            let writer=FileHandle(fileDescriptor:file,closeOnDealloc:true)
            defer {try? writer.close()}
            var remaining=min(partBytes,size-written)
            while remaining>0 {
                try control.waitWhilePaused()
                guard let data=try reader.read(upToCount:Int(min(remaining,1_048_576))),!data.isEmpty else {
                    throw ArchiveError.io("The source ended before the expected byte count.")
                }
                try writer.write(contentsOf:data)
                remaining-=UInt64(data.count);written+=UInt64(data.count)
                if Date().timeIntervalSince(lastProgress)>=0.1 || written==size {
                    lastProgress=Date()
                    progress?(ProgressEvent("phase.splitting",fraction:Double(written)/Double(size),bytes:written,entries:UInt64(index)))
                }
            }
            try writer.close()
        }
        var current=stat()
        guard fstat(descriptor,&current)==0,current.st_size==original.st_size else {throw ArchiveError.io("The source changed while splitting.")}
        #if os(macOS)
        let unchanged=current.st_mtimespec.tv_sec==original.st_mtimespec.tv_sec && current.st_mtimespec.tv_nsec==original.st_mtimespec.tv_nsec
        #else
        let unchanged=current.st_mtim.tv_sec==original.st_mtim.tv_sec && current.st_mtim.tv_nsec==original.st_mtim.tv_nsec
        #endif
        guard unchanged,written==size else {throw ArchiveError.io("The source changed while splitting.")}
        let (count,bytes)=try PathSafety.auditOutput(area.payload,limits:limits,quarantineSource:input,control:control)
        guard count==Int(partCount),bytes==size else {throw ArchiveError.io("The split archive is incomplete.")}
        try control.waitWhilePaused()
        let output=try area.commit(area.payload,to:parent.appendingPathComponent(basename+".parts"),policy:collision)
        progress?(ProgressEvent("phase.complete",fraction:1))
        return OperationResult(outputs:[output],entries:count,bytes:bytes)
    }
}
