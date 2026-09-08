import Foundation
import ArcoraCore
#if os(macOS)
import Darwin
#else
import Glibc
#endif

struct Arguments {
    var command:String
    var positional:[String]=[]
    var options:[String:[String]]=[:]
    let flags:Set<String>=["password-stdin","no-verify","no-solid","no-header-encryption","help","acknowledge-rar-license"]
    init(_ args:[String]) throws {
        command=args.first ?? "help"
        var i=1,literal=false
        while i<args.count {
            let item=args[i]
            if item=="--" && !literal { literal=true; i+=1; continue }
            if item.hasPrefix("--") && !literal {
                let key=String(item.dropFirst(2))
                let values:Set<String>=["threads","dictionary","level","volume","zip-encryption","memory-mib","max-gib","collision","rar","to","name","select","format","output","rar-license-directory","rar-engine-directory"]
                guard flags.contains(key) || values.contains(key) else {throw ArchiveError.invalid("Unknown option: "+item)}
                guard key=="select" || options[key]==nil else {throw ArchiveError.invalid("Duplicate option: "+item)}
                if flags.contains(key) { options[key,default:[]].append("true") }
                else {
                    guard i+1<args.count else { throw ArchiveError.invalid("Missing value: "+item) }
                    i+=1; options[key,default:[]].append(args[i])
                }
            } else { positional.append(item) }
            i+=1
        }
    }
    func value(_ key:String)->String? { options[key]?.last }
    func integer(_ key:String,_ fallback:Int) throws -> Int {
        guard let value=value(key) else { return fallback }
        guard let n=Int(value) else { throw ArchiveError.invalid("Not an integer: --"+key) }; return n
    }
    func require(_ key:String) throws -> String { guard let value=value(key) else{throw ArchiveError.invalid("Required: --"+key)};return value }
}
let usage="""
Arcora — native archive tools

arcora inspect ARCHIVE [--password-stdin]
arcora extract ARCHIVE --to DIRECTORY [--name NAME] [--select PATH ...] [--password-stdin]
arcora create --format 7z|zip|rar|tar|tar.gz|tar.bz2|tar.xz|gz|bz2|xz --output FILE [options] -- INPUT...
arcora test ARCHIVE [--password-stdin]
arcora engines
arcora rar-package-info
arcora rar-package-import /path/to/rarmacos-ARCH-723.tar.gz
arcora rar-package-remove
arcora rar-license-status
arcora rar-license-import /path/to/rarreg.key --acknowledge-rar-license
arcora rar-license-remove

Options: --threads N, --dictionary MIB, --level 0|1|3|5|7|9,
         --volume '100 MiB', --zip-encryption AES256|ZipCrypto,
         --memory-mib N, --max-gib N, --collision rename|fail,
         --rar /path/to/licensed/rar (development CLI only), --no-solid, --no-verify,
         --no-header-encryption, --password-stdin
         --rar-license-directory PRIVATE_PROFILE (optional isolated license storage)
         --rar-engine-directory PRIVATE_PROFILE (optional isolated imported engine storage)
Passwords are read from stdin, never from command-line arguments.
Development CLI/tests accept ARCORA_7ZZ and ARCORA_RAR. Packaged apps ignore these environment overrides.
RAR download URLs are opened in the customer's browser; Arcora imports a local original package only.
Customer RAR creation requires the customer's own license; an imported file is verified by RAR.
"""
func main() throws {
    let args=try Arguments(Array(CommandLine.arguments.dropFirst()))
    if args.command=="help" || args.value("help") != nil { print(usage); return }
    let engineDirectory=args.value("rar-engine-directory").map{URL(fileURLWithPath:$0)}
    var engines=EngineLocations.discover(rar:args.value("rar").map{URL(fileURLWithPath:$0)},rarEngineDirectory:engineDirectory)
    engines.rarLicenseDirectory=args.value("rar-license-directory").map{URL(fileURLWithPath:$0)}
    #if os(macOS)
    if args.command.hasPrefix("rar-package-") {
        let store=RARInstallationStore(root:engineDirectory)
        switch args.command {
        case "rar-package-info":
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            print(String(decoding:try encoder.encode(store.package),as:UTF8.self))
        case "rar-package-import":
            guard args.positional.count==1 else {throw ArchiveError.invalid("Select one unchanged official RAR .tar.gz package.")}
            try store.importPackage(from:URL(fileURLWithPath:args.positional[0]))
            guard try store.installedExecutable() != nil else {throw ArchiveError.missingEngine("RAR import did not complete.")}
            print("{\"state\":\"imported\",\"licenseIncluded\":false,\"originalFileUntouched\":true}")
        case "rar-package-remove":
            try store.moveImportedCopyToTrash();print("{\"state\":\"missing\",\"originalFileUntouched\":true}")
        default:throw ArchiveError.invalid("Unknown package command.")
        }
        return
    }
    if args.command.hasPrefix("rar-license-") {
        let store=RARLicenseStore(root:engines.rarLicenseDirectory)
        switch args.command {
        case "rar-license-status":
            let state=engines.rar.map{store.status(using:$0)} ?? .missing
            print("{\"state\":\"\(state.rawValue)\",\"creationRequiresLicense\":\(engines.rarRequiresLicense)}")
        case "rar-license-import":
            guard args.positional.count==1 else {throw ArchiveError.invalid("Select one customer-owned rarreg.key.")}
            try store.importKey(from:URL(fileURLWithPath:args.positional[0]),using:engines.requireRAR(),rightsAcknowledged:args.value("acknowledge-rar-license") != nil)
            print("{\"state\":\"verified\"}")
        case "rar-license-remove":
            try store.moveImportedCopyToTrash();print("{\"state\":\"missing\",\"originalFileUntouched\":true}")
        default:throw ArchiveError.invalid("Unknown license command.")
        }
        return
    }
    #endif
    if args.command=="engines" {
        let values=["7zz":engines.sevenZip?.path ?? "missing","worker":engines.worker?.path ?? "missing","RAR":engines.rar?.path ?? "not configured","RARMode":engines.rarIsBundled ? "bundled" : engines.rarInstallationDirectory != nil ? "user-imported-original" : engines.rar == nil ? "unavailable" : "external","RARLicensePolicy":engines.rarRequiresLicense ? "customer-supplied-required" : "development-evaluation","libarchive":NativeArchive.version]
        let data=try JSONSerialization.data(withJSONObject:values,options:[.prettyPrinted,.sortedKeys]); print(String(decoding:data,as:UTF8.self)); return
    }
    var limits=SafetyLimits()
    let memory=try args.integer("memory-mib",Int(limits.maxMemoryBytes/1048576))
    let maxGiB=try args.integer("max-gib",200)
    guard memory>0,memory<1048576,maxGiB>0,maxGiB<1048576 else{throw ArchiveError.invalid("Invalid resource limits.")}
    limits.maxMemoryBytes=UInt64(memory)*1048576; limits.maxExpandedBytes=UInt64(maxGiB)*1073741824
    let service=ArchiveService(engines:engines,limits:limits),control=JobControl()
    signal(SIGINT,SIG_IGN)
    let interrupt=DispatchSource.makeSignalSource(signal:SIGINT,queue:.global())
    interrupt.setEventHandler{control.cancel()}; interrupt.resume(); defer{interrupt.cancel()}
    var password:Secret?
    if args.value("password-stdin") != nil {
        guard let line=readLine(strippingNewline:true) else { throw ArchiveError.passwordRequired }; password=try Secret(line)
    }
    defer{password?.clear()}
    let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys]
    let progress:ProgressSink={ value in
        if var data=try? JSONEncoder().encode(value) { data.append(10); try? FileHandle.standardError.write(contentsOf:data) }
    }
    let threads=try args.integer("threads",max(1,min(8,ProcessInfo.processInfo.activeProcessorCount)))
    guard (1...256).contains(threads) else{throw ArchiveError.invalid("Invalid thread count.")}
    guard let collision=CollisionPolicy(rawValue:args.value("collision") ?? "rename") else {throw ArchiveError.invalid("Invalid collision policy.")}
    var result:OperationResult?
    switch args.command {
    case "inspect","extract","test":
        guard args.positional.count==1,let first=args.positional.first else{throw ArchiveError.invalid("Missing archive path.")}
        let source=URL(fileURLWithPath:first)
        if args.command=="inspect" {
            let manifest=try service.inspect(source,password:password,control:control,progress:progress)
            print(String(decoding:try encoder.encode(manifest),as:UTF8.self))
        } else if args.command=="extract" {
            result=try service.extract(source,to:URL(fileURLWithPath:args.require("to")),name:args.value("name"),
                selection:args.options["select"].map(Set.init),password:password,threads:threads,collision:collision,control:control,progress:progress)
        } else { result=try service.test(source,password:password,threads:threads,control:control,progress:progress) }
    case "create":
        let output=URL(fileURLWithPath:try args.require("output"))
        var options=CompressionOptions()
        guard let format=ArchiveFormat(rawValue:try args.require("format")) else{throw ArchiveError.invalid("Unknown format.")}
        options.format=format; options.threads=threads
        options.level=try args.integer("level",format == .tar ? 0 : 5); options.dictionaryMiB=try args.integer("dictionary",32)
        options.volumeBytes=try VolumeResolver.parseSize(args.value("volume") ?? "")
        options.solid=args.value("no-solid")==nil; options.verifyAfterCreation=args.value("no-verify")==nil
        options.encryptHeaders=args.value("no-header-encryption")==nil
        if let value=args.value("zip-encryption") {
            guard let encryption=ZIPEncryption(rawValue:value) else{throw ArchiveError.invalid("Unknown ZIP encryption.")}; options.zipEncryption=encryption
        }
        result=try service.create(inputs:args.positional.map{URL(fileURLWithPath:$0)},in:output.deletingLastPathComponent(),name:output.lastPathComponent,
                                  options:options,password:password,collision:collision,control:control,progress:progress)
    default: throw ArchiveError.invalid("Unknown command. Run arcora help.")
    }
    if let result {
        let value:[String:Any]=["outputs":result.outputs.map{$0.path},"entries":result.entries,"bytes":result.bytes]
        print(String(decoding:try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]),as:UTF8.self))
    }
}
do { try main() } catch {
    let text="Arcora: \(error.localizedDescription)\n"
    try? FileHandle.standardError.write(contentsOf:Data(text.utf8))
    exit((error as? ArchiveError) == .cancelled ? 130 : 1)
}
