import Foundation

public final class ArchiveService: @unchecked Sendable {
    public let engines:EngineLocations
    public let limits:SafetyLimits
    private let runner=ProcessRunner()
    public init(engines:EngineLocations,limits:SafetyLimits=SafetyLimits()) { self.engines=engines; self.limits=limits }
    private func preferNative(_ url:URL)->Bool {
        let name=url.lastPathComponent.lowercased()
        return [".tar",".tar.gz",".tgz",".tar.bz2",".tbz2",".tbz",".tar.xz",".txz",".tar.zst",".tzst",".cpio",".pax",".xar",".ar"].contains{ name.hasSuffix($0) }
    }
    public func inspect(_ input:URL,password:Secret?=nil,control:JobControl=JobControl(),progress:ProgressSink?=nil) throws -> ArchiveManifest {
        try control.waitWhilePaused()
        let volumes=try VolumeResolver.resolve(input.standardizedFileURL)
        let source=volumes.first
        progress?(ProgressEvent("phase.reading",detail:source.lastPathComponent))
        let nativeFirst=(preferNative(source) && !volumes.isMultipart) || engines.sevenZip==nil
        if nativeFirst {
            do { return try inspectNative(source,password:password,control:control) }
            catch let error as ArchiveError {
                if error == .cancelled || error == .passwordRequired || error == .wrongPassword { throw error }
                guard engines.sevenZip != nil else { throw error }
            }
        }
        let result=try runner.run(EngineCommand(try engines.require7z(),SevenZipArguments.list(source),secret:password),
                                  control:control,timeout:min(limits.timeout,600),outputLimit:limits.maxListingBytes,captureAll:true)
        do { try ProcessRunner.requireSuccess(result,passwordSupplied:password != nil) }
        catch {
            if !nativeFirst,!volumes.isMultipart,result.output.lowercased().contains("cannot open the file as archive") {
                return try inspectNative(source,password:password,control:control)
            }
            throw error
        }
        let entries=try SLTParser.parse(result.output,limit:limits.maxEntries)
        try PathSafety.validate(entries,limits:limits)
        return ArchiveManifest(source:source,backend:.sevenZip,entries:entries,format:source.pathExtension.uppercased())
    }
    private func inspectNative(_ source:URL,password:Secret?,control:JobControl) throws -> ArchiveManifest {
        let result=try runner.run(workerCommand("list",source:source,password:password),control:control,
                                  timeout:min(limits.timeout,600),outputLimit:limits.maxListingBytes,captureAll:true)
        try ProcessRunner.requireSuccess(result,passwordSupplied:password != nil)
        let decoder=JSONDecoder()
        let entries=try result.output.split(separator:"\n").compactMap { line -> ArchiveEntry? in
            let message=try decoder.decode(WorkerMessage.self,from:Data(line.utf8))
            guard var item=message.entry else { return nil }
            item.path=try PathSafety.canonicalEntry(item.path); return item
        }
        try PathSafety.validate(entries,limits:limits)
        return ArchiveManifest(source:source,backend:.libarchive,entries:entries,format:source.pathExtension.uppercased())
    }
    public func test(_ input:URL,password:Secret?=nil,threads:Int=4,control:JobControl=JobControl(),progress:ProgressSink?=nil) throws -> OperationResult {
        let manifest=try inspect(input,password:password,control:control,progress:progress)
        try testManifest(manifest,password:password,threads:threads,control:control,progress:progress)
        progress?(ProgressEvent("phase.complete",fraction:1))
        return OperationResult(outputs:[],entries:manifest.entries.count,bytes:manifest.totalBytes)
    }
    private func testManifest(_ manifest:ArchiveManifest,password:Secret?,threads:Int,control:JobControl,progress:ProgressSink?) throws {
        progress?(ProgressEvent("phase.verifying"))
        if manifest.backend == .libarchive {
            try runProgress(workerCommand("test",source:manifest.source,password:password),phase:"phase.verifying",native:true,control:control,progress:progress)
        } else {
            try runProgress(EngineCommand(try engines.require7z(),SevenZipArguments.test(manifest.source,threads:threads),secret:password),phase:"phase.verifying",control:control,progress:progress)
        }
    }
    public func extract(_ input:URL,to parent:URL,name:String?=nil,selection:Set<String>?=nil,password:Secret?=nil,
                        threads:Int=4,collision:CollisionPolicy = .rename,control:JobControl=JobControl(),progress:ProgressSink?=nil) throws -> OperationResult {
        let manifest=try inspect(input,password:password,control:control,progress:progress)
        let outputName=name ?? Self.defaultFolderName(manifest.source)
        try PathSafety.safeFilename(outputName)
        let selected:[ArchiveEntry]
        if let selection {
            guard !selection.isEmpty else { throw ArchiveError.invalid("No entries selected.") }
            for path in selection { _=try PathSafety.canonicalEntry(path) }
            selected=manifest.entries.filter{ item in selection.contains{item.path==$0 || item.path.hasPrefix($0+"/")} }
            guard !selected.isEmpty else { throw ArchiveError.invalid("Selection does not exist in this archive.") }
        } else { selected=manifest.entries }
        let expanded=selected.reduce(UInt64(0)){$0+$1.size}
        try PathSafety.requireFreeSpace(at:parent,bytes:expanded)
        let area=try Workspace(parent:parent)
        let list:URL?
        if selection != nil {
            let url=area.scratch.appendingPathComponent("selection.txt")
            try Data((selected.map{$0.path}.joined(separator:"\n")+"\n").utf8).write(to:url,options:.atomic)
            list=url
        } else { list=nil }
        let command:EngineCommand
        if manifest.backend == .libarchive {
            command=try workerCommand("extract",source:manifest.source,destination:area.payload,password:password,selection:list)
        } else {
            command=EngineCommand(try engines.require7z(),SevenZipArguments.extract(manifest.source,to:area.payload,threads:threads,selectionList:list),secret:password)
        }
        progress?(ProgressEvent("phase.extracting",detail:manifest.source.lastPathComponent))
        let monitor=OutputWatchdog(root:area.payload,limits:limits,control:control)
        monitor.start()
        do {
            try runProgress(command,phase:"phase.extracting",native:manifest.backend == .libarchive,control:control,progress:progress)
        } catch {
            monitor.stop()
            if let failure=monitor.failure { throw failure }
            throw error
        }
        monitor.stop()
        if let failure=monitor.failure { throw failure }
        try control.waitWhilePaused()
        progress?(ProgressEvent("phase.checking"))
        let (count,bytes)=try PathSafety.auditOutput(area.payload,limits:limits,quarantineSource:manifest.source,control:control)
        // A changed source or incomplete extraction must not silently publish a success.
        for item in selected where !item.isDirectory {
            let target=area.payload.appendingPathComponent(item.path)
            let values=try target.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
            guard values.isRegularFile==true,UInt64(max(0,values.fileSize ?? 0))==item.size else { throw ArchiveError.io("An expected entry was not completely extracted: "+item.path) }
        }
        try control.waitWhilePaused()
        progress?(ProgressEvent("phase.committing"))
        let final=try area.commit(area.payload,to:parent.appendingPathComponent(outputName,isDirectory:true),policy:collision)
        progress?(ProgressEvent("phase.complete",fraction:1))
        return OperationResult(outputs:[final],entries:count,bytes:bytes)
    }
    public func create(inputs:[URL],in parent:URL,name:String,options:CompressionOptions,password:Secret?=nil,
                       collision:CollisionPolicy = .rename,control:JobControl=JobControl(),progress:ProgressSink?=nil) throws -> OperationResult {
        try options.validate(hasPassword:password != nil)
        var rarConfiguration:URL?
        #if os(macOS)
        if options.format == .rar {
            let license=RARLicenseStore(root:engines.rarLicenseDirectory)
            rarConfiguration=try license.configurationForCreation(using:engines.requireRAR(),requiresLicense:engines.rarRequiresLicense,control:control)
        }
        #endif
        if options.format == .zip,let password {
            let valid=password.withBytes { bytes in bytes.allSatisfy{$0>=32 && $0<127} && (options.zipEncryption != .aes256 || bytes.count<=99) }
            guard valid else {throw ArchiveError.invalid("ZIP creation requires an ASCII password (up to 99 characters for AES). Choose 7z or RAR for Unicode passwords.")}
        }
        try PathSafety.safeFilename(name)
        guard options.estimatedMemoryBytes<=limits.maxMemoryBytes else {
            throw ArchiveError.resourceLimit("Estimated codec memory exceeds the configured budget; reduce dictionary size or thread count.")
        }
        progress?(ProgressEvent("phase.preparing"))
        let source=try PathSafety.validateInputs(inputs,outputParent:parent,limits:limits,control:control)
        if options.format == .rar {
            // RAR list files still interpret wildcard masks. Reject ambiguous
            // explicit source masks rather than silently archive extra files.
            if source.contains(where:{$0.path.contains("*") || $0.path.contains("?")}) {
                throw ArchiveError.unsupported("RAR source paths cannot contain wildcard characters. Use 7z or ZIP for these names.")
            }
            if let password,password.withBytes({String(decoding:$0,as:UTF8.self).utf16.count})>127 {
                throw ArchiveError.invalid("RAR passwords are limited to 127 UTF-16 code units in this adapter.")
            }
        }
        if options.format.singleStream {
            guard source.count==1,try source[0].resourceValues(forKeys:[.isRegularFileKey]).isRegularFile==true else {
                throw ArchiveError.invalid("GZIP, BZIP2 and XZ compress one file. Choose the TAR variant for files and folders.")
            }
        }
        let area=try Workspace(parent:parent)
        let outputName=name.lowercased().hasSuffix("."+options.format.rawValue) ? name : name+"."+options.format.rawValue
        try PathSafety.safeFilename(outputName)
        let output=area.payload.appendingPathComponent(outputName)
        let common=Self.commonParent(source)
        let expected=options.format == .rar ? try sourceManifest(source,relativeTo:common,control:control) : nil
        let inputList=area.scratch.appendingPathComponent("inputs.txt")
        let relative=source.map { "./"+String($0.path.dropFirst(common.path=="/" ? 1 : common.path.count+1)) }
        // RAR strips surrounding whitespace from unquoted list-file entries.
        let listed=options.format == .rar ? relative.map{"\""+$0+"\""} : relative
        try Data((listed.joined(separator:"\n")+"\n").utf8).write(to:inputList,options:.atomic)
        var actualOptions=options,actualList=inputList,directory=common
        if options.format.wrappedTar {
            let tar=area.scratch.appendingPathComponent("payload.tar")
            var tarOptions=CompressionOptions(); tarOptions.format = .tar; tarOptions.level=0; tarOptions.threads=1
            try runProgress(EngineCommand(try engines.require7z(),SevenZipArguments.create(tar,list:inputList,options:tarOptions,password:false),directory:common),phase:"phase.packing",control:control,progress:progress)
            actualOptions.format=options.format == .tarGzip ? .gzip : options.format == .tarBzip2 ? .bzip2 : .xz
            actualList=area.scratch.appendingPathComponent("tar-input.txt")
            try Data("./payload.tar\n".utf8).write(to:actualList,options:.atomic)
            directory=area.scratch
        }
        let command:EngineCommand
        if options.format == .rar {
            command=EngineCommand(try engines.requireRAR(),RARArguments.create(output,list:actualList,options:actualOptions,password:password != nil),directory:directory,secret:password,passwordCopies:1,rarConfigurationDirectory:rarConfiguration,redactRARRegistration:true)
        } else {
            command=EngineCommand(try engines.require7z(),SevenZipArguments.create(output,list:actualList,options:actualOptions,password:password != nil),directory:directory,secret:password)
        }
        try runProgress(command,phase:"phase.compressing",control:control,progress:progress)
        let files=try FileManager.default.contentsOfDirectory(at:area.payload,includingPropertiesForKeys:[.fileSizeKey,.isRegularFileKey]).sorted{$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending}
        guard !files.isEmpty else { throw ArchiveError.io("The engine produced no archive.") }
        let first:URL
        if options.volumeBytes != nil {
            first=try VolumeResolver.resolve(files[0]).first
        } else {
            guard FileManager.default.fileExists(atPath:output.path),files.count==1 else { throw ArchiveError.io("Unexpected output from archive engine.") }
            first=output
        }
        if options.verifyAfterCreation {
            if options.format == .rar {
                try runProgress(EngineCommand(try engines.requireRAR(),RARArguments.test(first,threads:options.threads,password:password != nil),secret:password,passwordCopies:1,rarConfigurationDirectory:rarConfiguration,redactRARRegistration:true),phase:"phase.verifying",control:control,progress:progress)
            } else {
                try runProgress(EngineCommand(try engines.require7z(),SevenZipArguments.test(first,threads:options.threads),secret:password),phase:"phase.verifying",control:control,progress:progress)
            }
        }
        if let expected {
            let manifest=try inspect(first,password:password,control:control)
            let actual=Dictionary(manifest.entries.map{($0.path,$0)},uniquingKeysWith:{old,_ in old})
            guard expected.count==actual.count,expected.allSatisfy({item in
                guard let value=actual[item.path] else {return false}
                return item.isDirectory==value.isDirectory && (item.isDirectory || item.size==value.size)
            }) else {throw ArchiveError.io("RAR contents differ from the selected inputs. A source may have changed or been skipped; no output was published.")}
        }
        let (_,bytes)=try PathSafety.auditOutput(area.payload,limits:limits,control:control)
        try control.waitWhilePaused()
        progress?(ProgressEvent("phase.committing"))
        let final:URL
        if options.volumeBytes != nil {
            // Publish the volume set via ONE exclusive directory rename. A half-committed
            // collection of part files can never be mistaken for a completed result.
            final=try area.commit(area.payload,to:parent.appendingPathComponent(outputName+".parts",isDirectory:true),policy:collision)
        } else { final=try area.commit(output,to:parent.appendingPathComponent(outputName),policy:collision) }
        progress?(ProgressEvent("phase.complete",fraction:1))
        return OperationResult(outputs:[final],entries:expected?.count ?? 0,bytes:bytes)
    }
    private func sourceManifest(_ sources:[URL],relativeTo parent:URL,control:JobControl) throws -> [ArchiveEntry] {
        let fm=FileManager.default,keys:[URLResourceKey]=[.isDirectoryKey,.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]
        var entries=[ArchiveEntry]()
        func append(_ url:URL) throws {
            try control.waitWhilePaused()
            let value=try url.resourceValues(forKeys:Set(keys))
            guard value.isSymbolicLink != true,value.isDirectory==true || value.isRegularFile==true else {throw ArchiveError.unsafePath(url.path)}
            let path=try PathSafety.canonicalEntry(String(url.path.dropFirst(parent.path=="/" ? 1 : parent.path.count+1)))
            entries.append(ArchiveEntry(path:path,size:UInt64(max(0,value.isDirectory==true ? 0 : value.fileSize ?? 0)),isDirectory:value.isDirectory==true))
            guard entries.count<=limits.maxEntries else {throw ArchiveError.resourceLimit("Too many source entries.")}
        }
        for source in sources {
            try append(source)
            if try source.resourceValues(forKeys:[.isDirectoryKey]).isDirectory==true {
                var error:Error?
                guard let iterator=fm.enumerator(at:source,includingPropertiesForKeys:keys,errorHandler:{_,e in error=e;return false}) else {throw ArchiveError.io(source.path)}
                for case let url as URL in iterator {try append(url)}
                if let error {throw error}
            }
        }
        try PathSafety.validate(entries,limits:limits)
        return entries
    }
    private func workerCommand(_ action:String,source:URL,destination:URL?=nil,password:Secret?,selection:URL?=nil) throws -> EngineCommand {
        var args=[action,source.path]
        if let destination { args.append(destination.path) }
        args += ["--max-bytes",String(limits.maxExpandedBytes),"--max-entries",String(limits.maxEntries)]
        if let selection { args += ["--selection",selection.path] }
        return EngineCommand(try engines.requireWorker(),args,secret:password,passwordCopies:1)
    }
    private func runProgress(_ command:EngineCommand,phase:String,native:Bool=false,control:JobControl,progress:ProgressSink?) throws {
        progress?(ProgressEvent(phase))
        let framer=LineFramer(),decoder=JSONDecoder()
        var last=Date.distantPast
        let percent=try NSRegularExpression(pattern:"(?:^|\\s)([0-9]{1,3})%")
        let result=try runner.run(command,control:control,timeout:limits.timeout,onData:{ data in
            framer.consume(data) { line in
                if native {
                    if let message=try? decoder.decode(WorkerMessage.self,from:Data(line.utf8)),var event=message.progress {
                        event.phase=phase; progress?(event)
                    }
                } else if Date().timeIntervalSince(last)>=0.1,
                          let m=percent.firstMatch(in:line,range:NSRange(line.startIndex...,in:line)),
                          let r=Range(m.range(at:1),in:line),let value=Double(line[r]),value<=100 {
                    last=Date(); progress?(ProgressEvent(phase,fraction:value/100))
                }
            }
        })
        try ProcessRunner.requireSuccess(result,passwordSupplied:command.secret != nil)
    }
    public static func commonParent(_ urls:[URL])->URL {
        guard let first=urls.first else { return URL(fileURLWithPath:"/") }
        var parent=first.deletingLastPathComponent()
        while !urls.allSatisfy({PathSafety.contains(parent,$0)}) && parent.path != "/" { parent.deleteLastPathComponent() }
        return parent
    }
    public static func defaultFolderName(_ input:URL)->String {
        var name=input.lastPathComponent
        if name.range(of:"\\.[0-9]{3,}$",options:.regularExpression) != nil { name=(name as NSString).deletingPathExtension }
        if let range=name.range(of:"\\.part[0-9]+\\.rar$",options:[.regularExpression,.caseInsensitive]) { name=String(name[..<range.lowerBound]) }
        else if let suffix=[".tar.gz",".tar.bz2",".tar.xz",".tar.zst"].first(where:{name.lowercased().hasSuffix($0)}) { name=String(name.dropLast(suffix.count)) }
        else { name=(name as NSString).deletingPathExtension }
        return name.isEmpty ? "Archive" : name
    }
}

/// Soft safety watchdog for external engines. Libarchive also enforces the byte
/// limit on each read; a subprocess can overshoot between these periodic checks.
private final class OutputWatchdog: @unchecked Sendable {
    let root:URL,limits:SafetyLimits,control:JobControl
    let lock=NSLock()
    private let queue=DispatchQueue(label:"app.arcora.quota",qos:.utility)
    var timer:DispatchSourceTimer?
    private var stored:ArchiveError?
    var failure:ArchiveError? { lock.lock(); defer{lock.unlock()}; return stored }
    init(root:URL,limits:SafetyLimits,control:JobControl) { self.root=root; self.limits=limits; self.control=control }
    func start() {
        let source=DispatchSource.makeTimerSource(queue:queue)
        source.schedule(deadline:.now()+3,repeating:3)
        source.setEventHandler { [weak self] in self?.check() }; timer=source; source.resume()
    }
    func stop() { timer?.cancel(); timer=nil; queue.sync {} }
    private func check() {
        if control.isCancelled || control.isPaused { return }
        do {
            // No metadata mutations while the engine is writing: only sample sizes.
            var bytes:UInt64=0,count=0
            if let iterator=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.fileSizeKey,.isSymbolicLinkKey,.isRegularFileKey]) {
                for case let url as URL in iterator {
                    if control.isCancelled { return }
                    guard let v=try? url.resourceValues(forKeys:[.fileSizeKey,.isSymbolicLinkKey,.isRegularFileKey]) else { continue }
                    count+=1
                    if v.isSymbolicLink==true { throw ArchiveError.unsafePath(url.lastPathComponent) }
                    if v.isRegularFile==true {
                        let sum=bytes.addingReportingOverflow(UInt64(max(0,v.fileSize ?? 0)))
                        if sum.overflow { throw ArchiveError.resourceLimit("Expanded size overflow.") }; bytes=sum.partialValue
                    }
                    if bytes>limits.maxExpandedBytes || count>limits.maxEntries { throw ArchiveError.resourceLimit("Output limit exceeded.") }
                }
            }
        } catch let error as ArchiveError {
            lock.lock(); stored=error; lock.unlock(); control.cancel()
        } catch {}
    }
    deinit { timer?.cancel() }
}
