import Foundation

public struct EngineLocations: Sendable {
    public var sevenZip:URL?
    public var worker:URL?
    public var rar:URL?
    public var rarIsBundled:Bool
    public var rarInstallationDirectory:URL?
    public var rarRequiresLicense:Bool
    public var rarLicenseDirectory:URL?
    public init(sevenZip:URL?=nil,worker:URL?=nil,rar:URL?=nil,rarIsBundled:Bool=false,rarRequiresLicense:Bool?=nil,rarLicenseDirectory:URL?=nil,rarInstallationDirectory:URL?=nil) {
        self.sevenZip=sevenZip; self.worker=worker; self.rar=rar; self.rarIsBundled=rarIsBundled
        self.rarRequiresLicense=rarRequiresLicense ?? (rarIsBundled || rarInstallationDirectory != nil);self.rarLicenseDirectory=rarLicenseDirectory
        self.rarInstallationDirectory=rarInstallationDirectory
    }
    public static func discover(bundle:Bundle = .main,rar:URL?=nil,rarEngineDirectory:URL?=nil) -> EngineLocations {
        let fm=FileManager.default
        func executable(_ urls:[URL])->URL? { urls.first{fm.isExecutableFile(atPath:$0.path)} }
        let executableURL=bundle.executableURL ?? URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL
        let sibling=executableURL.deletingLastPathComponent()
        // The packaged CLI is inside Helpers; Bundle.main is not necessarily the app.
        let app=bundle.bundleURL.pathExtension == "app" ? bundle.bundleURL :
            (sibling.deletingLastPathComponent().lastPathComponent == "Contents" && sibling.deletingLastPathComponent().deletingLastPathComponent().pathExtension == "app" ? sibling.deletingLastPathComponent().deletingLastPathComponent() : nil)
        let helpers=(app ?? bundle.bundleURL).appendingPathComponent("Contents/Helpers")
        let cwd=URL(fileURLWithPath:fm.currentDirectoryPath)
        var zipCandidates=[helpers.appendingPathComponent("7zz")]
        var workerCandidates=[helpers.appendingPathComponent("arcora-worker")]
        #if arch(arm64)
        let architecture="arm64"
        #else
        let architecture="x86_64"
        #endif
        let bundledRAR=executable([helpers.appendingPathComponent("rar/"+architecture+"/rar")])
        var externalRAR=app == nil ? rar : nil
        // CLI/tests can explicitly opt into an engine override; packaged GUI ignores environment overrides.
        if app == nil {
            zipCandidates += [sibling.appendingPathComponent("7zz"),cwd.appendingPathComponent("Vendor/7zip/7zz")]
            workerCandidates.append(sibling.appendingPathComponent("arcora-worker"))
            if let value=ProcessInfo.processInfo.environment["ARCORA_7ZZ"] {zipCandidates.insert(URL(fileURLWithPath:value),at:0)}
            if externalRAR == nil,let value=ProcessInfo.processInfo.environment["ARCORA_RAR"] {externalRAR=URL(fileURLWithPath:value)}
        }
        var managedRAR:URL?,managedRoot:URL?
        #if os(macOS)
        let store=RARInstallationStore(root:rarEngineDirectory)
        managedRAR=try? store.installedExecutable()
        if managedRAR != nil {managedRoot=store.root}
        #endif
        let external=externalRAR.flatMap{executable([$0])}
        let selected=bundledRAR ?? external ?? managedRAR
        let managed=selected != nil && selected==managedRAR && bundledRAR==nil && external==nil
        return EngineLocations(sevenZip:executable(zipCandidates),worker:executable(workerCandidates),
            rar:selected,rarIsBundled:bundledRAR != nil,
            rarRequiresLicense:managed || (app != nil && (app.flatMap{Bundle(url:$0)?.object(forInfoDictionaryKey:"ArcoraRARLocalEvaluation")} as? Bool != true)),
            rarInstallationDirectory:managed ? managedRoot : nil)
    }
    public func require7z() throws -> URL { guard let p=sevenZip else { throw ArchiveError.missingEngine("7zz — run Scripts/bootstrap-engines.sh and Scripts/build-app.sh.") }; return p }
    public func requireWorker() throws -> URL { guard let p=worker else { throw ArchiveError.missingEngine("arcora-worker — build the native helper.") }; return p }
    public func requireRAR() throws -> URL {
        guard let p=rar,FileManager.default.isExecutableFile(atPath:p.path) else { throw ArchiveError.missingEngine("RAR creation engine is unavailable. In Settings > Engines, open the official download, import the original package, then import your own RAR license.") }
        #if os(macOS)
        if let root=rarInstallationDirectory {
            guard try RARInstallationStore(root:root).installedExecutable()==p else {throw ArchiveError.missingEngine("Reimport the official RAR package in Settings.")}
        }
        #endif
        return p
    }
}

public enum SevenZipArguments {
    public static func list(_ file:URL) -> [String] { ["l","-slt","-ba","-sccUTF-8","--",file.path] }
    public static func test(_ file:URL,threads:Int) -> [String] { ["t","-bsp1","-bso1","-bse1","-sccUTF-8","-mmt=\(threads)","--",file.path] }
    public static func extract(_ file:URL,to:URL,threads:Int,selectionList:URL?=nil) -> [String] {
        var result=["x","-y","-aos","-bsp1","-bso1","-bse1","-sccUTF-8","-scsUTF-8","-spd","-mmt=\(threads)","-o"+to.path]
        if let list=selectionList { result += ["-i@"+list.path] }
        result += ["--",file.path]
        return result
    }
    public static func create(_ output:URL,list:URL,options:CompressionOptions,password:Bool) -> [String] {
        var result=["a","-t"+options.format.sevenZipType,"-mx=\(options.level)","-mmt=\(options.threads)","-bsp1","-bso1","-bse1","-sccUTF-8","-scsUTF-8","-spd"]
        if options.format == .sevenZip {
            if options.level == 0 { result += ["-m0=Copy", "-ms=off"] }
            else { result += ["-m0=LZMA2","-md=\(options.dictionaryMiB)m",options.solid ? "-ms=on" : "-ms=off"] }
        } else if options.format == .xz || options.format == .tarXz { result += ["-md=\(options.dictionaryMiB)m"] }
        if options.format == .zip { result += [options.level == 0 ? "-mm=Copy" : "-mm=Deflate"] }
        if let bytes=options.volumeBytes { result += ["-v\(bytes)b"] }
        if password {
            result += ["-p"] // actual password is written to stdin, never here
            if options.format == .sevenZip { result += [options.encryptHeaders ? "-mhe=on" : "-mhe=off"] }
            if options.format == .zip { result += ["-mem="+options.zipEncryption.rawValue] }
        }
        // -- disables @list interpretation too; inclusion switches precede it.
        result += ["-i@"+list.path,"--",output.path]
        return result
    }
}
public enum RARArguments {
    public static func create(_ output:URL,list:URL,options:CompressionOptions,password:Bool) -> [String] {
        let level=[0:0,1:1,3:2,5:3,7:4,9:5][options.level] ?? 3
        var args=["a","-cfg-","-m\(level)","-md\(options.dictionaryMiB)m","-mt\(options.threads)","-scfl","-idn","-o-","-ol-",options.solid ? "-s" : "-s-"]
        if let size=options.volumeBytes { args.append("-v\(size)b") }
        if password { args.append(options.encryptHeaders ? "-hp" : "-p") }
        args += ["--",output.path,"@"+list.path]
        return args
    }
    public static func test(_ file:URL,threads:Int,password:Bool)->[String] {
        ["t","-cfg-","-mt\(threads)","-idn"]+(password ? ["-p"] : [])+["--",file.path]
    }
}

public enum SLTParser {
    public static func parse(_ text:String,limit:Int=250000) throws -> [ArchiveEntry] {
        var result=[ArchiveEntry](),record=[String:String]()
        let date=DateFormatter(); date.locale=Locale(identifier:"en_US_POSIX"); date.dateFormat="yyyy-MM-dd HH:mm:ss"
        func flush() throws {
            defer { record.removeAll(keepingCapacity:true) }
            guard let path=record["Path"] else { return }
            if record["Type"] != nil && record["Size"]==nil && record["Folder"]==nil { return }
            guard result.count<limit else { throw ArchiveError.resourceLimit("Too many archive entries.") }
            let attributes=record["Attributes"] ?? ""
            let unix=record["Mode"] ?? record["Characteristics"] ?? ""
            let link=[record["Symbolic Link"],record["Hard Link"]].compactMap{$0}.first{!$0.isEmpty}
            let isLink=link != nil || unix.hasPrefix("l") || attributes.contains(" lrwx") || attributes.hasPrefix("lrwx")
            let isSpecial=unix.hasPrefix("b") || unix.hasPrefix("c") || unix.hasPrefix("p") || unix.hasPrefix("s")
            let rawSize=record["Size"] ?? "0"
            guard let size=UInt64(rawSize.isEmpty ? "0" : rawSize) else { throw ArchiveError.invalid("Invalid size in archive listing.") }
            let normalized=try PathSafety.canonicalEntry(path)
            result.append(ArchiveEntry(path:normalized,size:size,packedSize:record["Packed Size"].flatMap(UInt64.init),
                modified:record["Modified"].flatMap{date.date(from:String($0.prefix(19)))},
                isDirectory:record["Folder"]=="+" || attributes.first=="D" || unix.hasPrefix("d"),
                isEncrypted:record["Encrypted"]=="+",isUnsafeType:isLink || isSpecial,linkTarget:link))
        }
        for raw in text.components(separatedBy:"\n") {
            let line=raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line.isEmpty { try flush(); continue }
            if line.hasPrefix("----------") || line=="--" { try flush(); continue }
            guard let divider=line.range(of:" = ") else {
                // A filename containing a newline must not forge a structured record.
                if !record.isEmpty { throw ArchiveError.unsafePath("Ambiguous multiline archive metadata.") }
                continue
            }
            let key=String(line[..<divider.lowerBound]),value=String(line[divider.upperBound...])
            if record[key] != nil { throw ArchiveError.unsafePath("Duplicate fields in archive metadata.") }
            record[key]=value
        }
        try flush()
        return result
    }
}
