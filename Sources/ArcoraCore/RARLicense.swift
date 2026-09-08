#if os(macOS)
import Foundation
import CryptoKit

public enum RARLicenseState:String,Codable,Sendable {
    case missing,unconfirmed,rejected,verified,verificationFailed
    public var localizationKey:String { "rar.license."+rawValue }
}

/// Customer-owned key storage, separate from the signed app and from other RAR installations.
/// This checks the official engine's response, not license ownership or purchased seat counts.
public struct RARLicenseStore:Sendable {
    public let root:URL
    public var configurationDirectory:URL { root.appendingPathComponent("config",isDirectory:true) }
    public var keyDirectory:URL { configurationDirectory.appendingPathComponent("rar",isDirectory:true) }
    public var keyURL:URL { keyDirectory.appendingPathComponent("rarreg.key") }
    private var receiptURL:URL { keyDirectory.appendingPathComponent("arcora-acceptance.json") }
    private let verify:@Sendable (URL,URL,String,JobControl)throws->Bool
    public init(root:URL?=nil) {
        self.root=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("Arcora/RARLicense",isDirectory:true)
        verify={engine,configuration,owner,control in try Self.verifyWithOfficialEngine(engine,configuration,owner,control)}
    }
    // Dependency injection is internal and used only with non-license test data.
    init(root:URL,verify:@escaping @Sendable (URL,URL,String,JobControl)throws->Bool) {
        self.root=root;self.verify=verify
    }
    private struct Acceptance:Codable { let schema:Int;let keySHA256:String;let rightsAcknowledged:Bool }
    private static func digest(_ data:Data)->String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
    private static func read(_ file:URL,maxBytes:Int=16_384)throws->Data {
        let values=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile==true,values.isSymbolicLink != true,(values.fileSize ?? 0)<=maxBytes else {
            throw ArchiveError.licenseRequired("Choose a regular RAR license file no larger than 16 KiB; links and archives are not accepted.")
        }
        let handle=try FileHandle(forReadingFrom:file);defer{try? handle.close()}
        let data=try handle.read(upToCount:maxBytes+1) ?? Data()
        guard !data.isEmpty,data.count<=maxBytes else {throw ArchiveError.licenseRequired("The license file is empty or too large.")}
        return data
    }
    static func owner(in data:Data)throws->String {
        guard let text=String(data:data,encoding:.utf8),!text.contains("\0") else {throw ArchiveError.licenseRequired("This is not a supported RAR license file.")}
        let lines=text.replacingOccurrences(of:"\r\n",with:"\n").trimmingCharacters(in:CharacterSet(charactersIn:"\u{FEFF}")).components(separatedBy:"\n")
        guard lines.count>=5,lines[0]=="RAR registration data",!lines[1].trimmingCharacters(in:.whitespaces).isEmpty,
              lines[1].rangeOfCharacter(from:.controlCharacters)==nil,lines[3].hasPrefix("UID=") else {
            throw ArchiveError.licenseRequired("Select the original rarreg.key received from RARLAB or an authorized reseller, not a serial number or purchase receipt.")
        }
        return lines[1].trimmingCharacters(in:.whitespaces)
    }
    private func checkDirectories()throws {
        for directory in [root,configurationDirectory,keyDirectory] where FileManager.default.fileExists(atPath:directory.path) {
            let values=try directory.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard values.isDirectory==true,values.isSymbolicLink != true else {throw ArchiveError.licenseRequired("The private license directory is not a regular directory.")}
        }
    }
    private func acceptedData()throws->Data? {
        try checkDirectories()
        guard FileManager.default.fileExists(atPath:keyURL.path) else {return nil}
        let data=try Self.read(keyURL)
        guard let receipt=try? JSONDecoder().decode(Acceptance.self,from:Self.read(receiptURL)),receipt.schema==1,
              receipt.rightsAcknowledged,receipt.keySHA256==Self.digest(data) else {throw ArchiveError.licenseRequired("Import this license and confirm that its usage rights cover this computer.")}
        return data
    }
    public func status(using engine:URL,control:JobControl=JobControl())->RARLicenseState {
        do {
            guard let data=try acceptedData() else {return .missing}
            let owner=try Self.owner(in:data)
            return try verify(engine,configurationDirectory,owner,control) ? .verified : .rejected
        } catch ArchiveError.licenseRequired {return .unconfirmed}
        catch {return .verificationFailed}
    }
    public func requireVerified(using engine:URL,control:JobControl=JobControl())throws {
        try control.check()
        guard status(using:engine,control:control) == .verified else {
            try control.check()
            throw ArchiveError.licenseRequired("RAR creation is locked. Import your own valid rarreg.key in Settings and confirm that its license covers this computer. RAR extraction remains available.")
        }
    }
    func configurationForCreation(using engine:URL,requiresLicense:Bool,control:JobControl=JobControl())throws->URL {
        try control.check()
        if requiresLicense {try requireVerified(using:engine,control:control)}
        // Local evaluation builds must also pass the user's imported configuration
        // so a subsequently purchased license is actually used by creation/testing.
        return configurationDirectory
    }
    public func importKey(from file:URL,using engine:URL,rightsAcknowledged:Bool,control:JobControl=JobControl())throws {
        guard rightsAcknowledged else {throw ArchiveError.licenseRequired("Confirm that you own or are authorized to use this license on this computer.")}
        let data=try Self.read(file),owner=try Self.owner(in:data)
        try checkDirectories()
        let fm=FileManager.default
        try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:root.path)
        let staging=root.appendingPathComponent(".import-"+UUID().uuidString,isDirectory:true)
        let candidate=RARLicenseStore(root:staging,verify:verify)
        defer{try? fm.removeItem(at:staging)}
        try fm.createDirectory(at:candidate.keyDirectory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try data.write(to:candidate.keyURL,options:.atomic)
        try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:candidate.keyURL.path)
        guard try verify(engine,candidate.configurationDirectory,owner,control) else {
            throw ArchiveError.licenseRequired("The official RAR engine did not confirm this license. The previous license was kept; contact your license issuer if necessary.")
        }
        let receipt=Acceptance(schema:1,keySHA256:Self.digest(data),rightsAcknowledged:true)
        try JSONEncoder().encode(receipt).write(to:candidate.receiptURL,options:.atomic)
        try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:candidate.receiptURL.path)
        try fm.createDirectory(at:configurationDirectory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try control.check()
        if fm.fileExists(atPath:keyDirectory.path) {
            // Replace the entire verified key+receipt transaction, preserving the old directory on error.
            _=try fm.replaceItemAt(keyDirectory,withItemAt:candidate.keyDirectory)
        } else {try fm.moveItem(at:candidate.keyDirectory,to:keyDirectory)}
    }
    /// Only the application-owned copy is moved to Trash; the customer's original is untouched.
    public func moveImportedCopyToTrash()throws {
        try checkDirectories()
        if FileManager.default.fileExists(atPath:keyDirectory.path) {try FileManager.default.trashItem(at:keyDirectory,resultingItemURL:nil)}
    }
    static func registeredOwnerMatches(_ output:String,owner:String)->Bool {
        // Fail closed on unrecognized versions/formats; never equate a successful exit to registration.
        let lines=output.components(separatedBy:.newlines).map{$0.trimmingCharacters(in:.whitespaces)}
        guard lines.contains(where:{$0.hasPrefix("RAR ") && $0.contains("Alexander Roshal")}),
              !lines.contains(where:{$0.localizedCaseInsensitiveContains("trial version") || $0.localizedCaseInsensitiveContains("evaluation copy")}) else {return false}
        let registrations=lines.filter{$0.hasPrefix("Registered to ") || $0.hasPrefix("Registered to:")}
        guard registrations.count==1 else {return false}
        let value=String(registrations[0].dropFirst("Registered to".count)).trimmingCharacters(in:CharacterSet(charactersIn:" :\t"))
        return value.precomposedStringWithCanonicalMapping==owner.precomposedStringWithCanonicalMapping
    }
    private static func verifyWithOfficialEngine(_ engine:URL,_ configuration:URL,_ owner:String,_ control:JobControl)throws->Bool {
        // Official order.htm documents $XDG_CONFIG_HOME/rar/rarreg.key on macOS.
        // HOME is not changed and no global RAR installation or registration file is modified.
        let result=try ProcessRunner().run(EngineCommand(engine,["-cfg-"],directory:configuration,
            rarConfigurationDirectory:configuration),control:control,timeout:10,outputLimit:65_536,captureAll:true)
        return result.status==0 && registeredOwnerMatches(result.output,owner:owner)
    }
}
#endif
