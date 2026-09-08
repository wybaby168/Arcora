#if os(macOS)
import Foundation
import XCTest
@testable import ArcoraCore

final class RARLicenseTests:ArcoraTestCase {
    // Intentionally NOT a usable license. Only plumbing tests inject a local validator.
    private func invalidTestData(_ name:String="Arcora Test",body:String="NOT_A_LICENSE")->Data {
        Data("RAR registration data\n\(name)\nTEST DATA ONLY\nUID=INVALID\n\(body)\n".utf8)
    }
    private var engine:URL {URL(fileURLWithPath:"/bin/echo")}
    private var root:URL {temp.appendingPathComponent("private-license")}
    private func file(_ data:Data,name:String="customer-original.key")throws->URL {
        let path=temp.appendingPathComponent(name);try data.write(to:path);return path
    }
    private func mockStore()->RARLicenseStore {
        RARLicenseStore(root:root,verify:{_,configuration,_,_ in
            let data=try Data(contentsOf:configuration.appendingPathComponent("rar/rarreg.key"))
            return !String(decoding:data,as:UTF8.self).contains("REJECT")
        })
    }
    func testMissingLicenseIsNotActivated() {
        XCTAssertEqual(RARLicenseStore(root:root).status(using:engine),.missing)
    }
    func testLocalEvaluationUsesPrivateLicenseConfigurationWithoutWeakeningCustomerGate()throws {
        let store=RARLicenseStore(root:root)
        XCTAssertEqual(try store.configurationForCreation(using:engine,requiresLicense:false),store.configurationDirectory)
        XCTAssertThrowsError(try store.configurationForCreation(using:engine,requiresLicense:true))
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.path))
    }
    func testMalformedAndEmptyInputRejected() {
        for data in [Data(),Data("receipt".utf8),Data("RAR registration data\nName\nLicense\nUID=1\n\0".utf8)] {
            XCTAssertThrowsError(try RARLicenseStore.owner(in:data))
        }
    }
    func testExplicitRightsAcknowledgmentRequired()throws {
        let original=try file(invalidTestData())
        XCTAssertThrowsError(try mockStore().importKey(from:original,using:engine,rightsAcknowledged:false))
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.path))
    }
    func testPrivateCopyPreservesOriginalAndUsesRestrictedPermissions()throws {
        let data=invalidTestData(),original=try file(data),store=mockStore()
        try store.importKey(from:original,using:engine,rightsAcknowledged:true)
        XCTAssertEqual(try Data(contentsOf:store.keyURL),data)
        XCTAssertEqual(try Data(contentsOf:original),data)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath:store.keyURL.path)[.posixPermissions] as? Int,0o600)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath:root.path)[.posixPermissions] as? Int,0o700)
        XCTAssertEqual(store.status(using:engine),.verified)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:root.path).contains{$0.hasPrefix(".import-")})
    }
    func testRejectedReplacementPreservesPreviousKey()throws {
        let store=mockStore(),data=invalidTestData(),first=try file(data),second=try file(invalidTestData(body:"REJECT"),name:"rejected.key")
        try store.importKey(from:first,using:engine,rightsAcknowledged:true)
        XCTAssertThrowsError(try store.importKey(from:second,using:engine,rightsAcknowledged:true))
        XCTAssertEqual(try Data(contentsOf:store.keyURL),data)
        XCTAssertEqual(store.status(using:engine),.verified)
    }
    func testAcceptedReplacementIsAtomicWithReceipt()throws {
        let store=mockStore(),first=try file(invalidTestData()),secondData=invalidTestData("Second Test"),second=try file(secondData,name:"replacement.key")
        try store.importKey(from:first,using:engine,rightsAcknowledged:true)
        try store.importKey(from:second,using:engine,rightsAcknowledged:true)
        XCTAssertEqual(try Data(contentsOf:store.keyURL),secondData)
        XCTAssertEqual(store.status(using:engine),.verified)
        XCTAssertTrue(FileManager.default.fileExists(atPath:first.path))
    }
    func testTamperedKeyInvalidatesAcknowledgment()throws {
        let store=mockStore(),original=try file(invalidTestData())
        try store.importKey(from:original,using:engine,rightsAcknowledged:true)
        try invalidTestData("Changed").write(to:store.keyURL)
        XCTAssertEqual(store.status(using:engine),.unconfirmed)
        XCTAssertThrowsError(try store.requireVerified(using:engine))
    }
    func testSymlinksAndOversizeFilesRejected()throws {
        let original=try file(invalidTestData()),link=temp.appendingPathComponent("link.key")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:original)
        XCTAssertThrowsError(try mockStore().importKey(from:link,using:engine,rightsAcknowledged:true))
        let large=try file(Data(repeating:65,count:16_385),name:"large.key")
        XCTAssertThrowsError(try mockStore().importKey(from:large,using:engine,rightsAcknowledged:true))
        try FileManager.default.createSymbolicLink(at:root,withDestinationURL:temp)
        XCTAssertThrowsError(try mockStore().importKey(from:original,using:engine,rightsAcknowledged:true))
        XCTAssertEqual(try Data(contentsOf:original),invalidTestData())
    }
    func testOnlyRecognizedRegistrationBannerMatchesOwner() {
        let header="RAR 7.23 Copyright (c) Alexander Roshal\n"
        XCTAssertTrue(RARLicenseStore.registeredOwnerMatches(header+"Registered to Arcora Test\n",owner:"Arcora Test"))
        for output in [header+"Trial version",header+"Registered to Other",header+"Registered to Arcora Test\nTrial version",header+"Registered to Arcora Test\nRegistered to Other","Registered to Arcora Test"] {
            XCTAssertFalse(RARLicenseStore.registeredOwnerMatches(output,owner:"Arcora Test"))
        }
    }
    func testCustomerCreateCannotBypassLicenseThroughService()throws {
        let input=try touch("input.txt"),store=RARLicenseStore(root:root)
        let locations=EngineLocations(rar:engine,rarIsBundled:true,rarRequiresLicense:true,rarLicenseDirectory:store.root)
        var options=CompressionOptions();options.format = .rar
        XCTAssertThrowsError(try ArchiveService(engines:locations).create(inputs:[input],in:temp,name:"blocked",options:options)) {
            guard case .licenseRequired = $0 as? ArchiveError else {return XCTFail("Expected licenseRequired")}
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent("blocked.rar").path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:temp.path).contains{$0.hasPrefix(".arcora-")})
    }
    func testOfficialEngineRejectsNonLicenseTestData()throws {
        guard let rar=EngineLocations.discover(rarEngineDirectory:temp.appendingPathComponent("managed-rar")).rar else {
            if ProcessInfo.processInfo.environment["ARCORA_REQUIRE_RAR"]=="1" {throw ArchiveError.missingEngine("Official RAR required for license rejection test.")}
            throw XCTSkip("Official RAR unavailable")
        }
        let original=try file(invalidTestData()),store=RARLicenseStore(root:root)
        XCTAssertThrowsError(try store.importKey(from:original,using:rar,rightsAcknowledged:true))
        XCTAssertEqual(store.status(using:rar),.missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath:store.keyURL.path))
        XCTAssertEqual(try Data(contentsOf:original),invalidTestData())
    }
    func testOnlyExplicitCommandSetsPrivateConfigEnvironment()throws {
        let configuration=temp.appendingPathComponent("private-config")
        let result=try ProcessRunner().run(EngineCommand(URL(fileURLWithPath:"/usr/bin/env"),[],rarConfigurationDirectory:configuration))
        XCTAssertTrue(result.output.contains("XDG_CONFIG_HOME="+configuration.path))
        XCTAssertTrue(result.output.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
        XCTAssertFalse(result.output.contains("RARINISWITCHES="))
        let other=try ProcessRunner().run(EngineCommand(URL(fileURLWithPath:"/usr/bin/env"),[]))
        XCTAssertFalse(other.output.contains("XDG_CONFIG_HOME="))
    }
    func testRARRegistrationDetailsAreRedacted()throws {
        let result=try ProcessRunner().run(EngineCommand(engine,["Registered to PRIVATE_TEST_OWNER"],redactRARRegistration:true))
        XCTAssertFalse(result.output.contains("PRIVATE_TEST_OWNER"))
        XCTAssertTrue(result.output.contains("<private>"))
    }
}
#endif
