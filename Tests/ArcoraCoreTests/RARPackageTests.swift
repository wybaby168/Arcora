#if os(macOS)
import Foundation
import CryptoKit
import Darwin
import XCTest
@testable import ArcoraCore

final class RARPackageTests:ArcoraTestCase {
    private var project:URL {URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private var root:URL {temp.appendingPathComponent("private-engine")}
    private func original(_ package:RARPackage = .current)throws->URL {
        let path=project.appendingPathComponent(".local/rar/downloads/"+package.filename)
        guard FileManager.default.fileExists(atPath:path.path) else {
            if ProcessInfo.processInfo.environment["ARCORA_REQUIRE_RAR_PACKAGE"]=="1" {throw ArchiveError.missingEngine("Official original RAR packages required for import tests.")}
            throw XCTSkip("Original RAR package not locally available; never downloaded by unit tests")
        }
        return path
    }
    private func digest(_ url:URL)throws->String {SHA256.hash(data:try Data(contentsOf:url)).map{String(format:"%02x",$0)}.joined()}
    func testArchitectureSelectionUsesHardwareNotProcessTranslation() {
        XCTAssertEqual(RARPackage.forHardware(arm64:true),.arm64)
        XCTAssertEqual(RARPackage.forHardware(arm64:false),.x86_64)
        XCTAssertTrue([RARPackage.arm64,.x86_64].contains(.current))
    }
    func testDownloadMetadataMatchesReviewedUpstreamLock()throws {
        let json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:project.appendingPathComponent("Vendor/engines.lock.json"))) as? [String:Any])
        let rar=try XCTUnwrap(json["rar"] as? [String:Any])
        XCTAssertEqual(rar["bundled"] as? Bool,false)
        for package in [RARPackage.arm64,.x86_64] {
            let item=try XCTUnwrap(rar[package.architecture] as? [String:String])
            XCTAssertEqual(package.version,rar["version"] as? String)
            XCTAssertEqual(package.filename,item["file"])
            XCTAssertEqual(package.sha256,item["sha256"])
            XCTAssertEqual(package.binarySha256,item["binarySha256"])
            XCTAssertEqual(package.downloadURL.absoluteString,item["url"])
            XCTAssertEqual(package.downloadURL.scheme,"https")
            XCTAssertEqual(package.downloadURL.host,"www.rarlab.com")
        }
    }
    func testMissingInstallationDoesNotCreateDirectories()throws {
        XCTAssertNil(try RARInstallationStore(root:root).installedExecutable())
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.path))
    }
    func testBothOfficialOriginalsImportWithManualsAndUnchangedBytes()throws {
        for package in [RARPackage.arm64,.x86_64] {
            let source=try original(package),before=try digest(source)
            let store=RARInstallationStore(root:root.appendingPathComponent(package.architecture),package:package)
            try store.importPackage(from:source)
            XCTAssertEqual(try store.installedExecutable(),store.executable)
            XCTAssertEqual(try digest(source),before)
            XCTAssertEqual(try digest(store.originalPackage),package.sha256)
            XCTAssertEqual(try digest(store.executable),package.binarySha256)
            for name in ["license.txt","rar.txt","order.htm","acknow.txt","readme.txt","whatsnew.txt","unrar","default.sfx","rarfiles.lst"] {
                XCTAssertTrue(FileManager.default.fileExists(atPath:store.installation.appendingPathComponent("rar/"+name).path),name)
            }
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath:store.executable.path)[.posixPermissions] as? Int,0o700)
            XCTAssertFalse(FileManager.default.fileExists(atPath:store.installation.appendingPathComponent("rar/rarreg.key").path))
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:store.root.path).contains{$0.hasPrefix(".import-")})
        }
    }
    func testWrongArchitectureRejectedBeforeWriting()throws {
        let store=RARInstallationStore(root:root,package:.arm64)
        XCTAssertThrowsError(try store.importPackage(from:original(.x86_64))) {
            XCTAssertTrue($0.localizedDescription.contains("Wrong architecture"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.path))
    }
    func testModifiedAndTruncatedPackagesRejectedBeforeExtraction()throws {
        let data=try Data(contentsOf:original()),store=RARInstallationStore(root:root)
        var modified=data;modified[modified.count/2] ^= 1
        for payload in [modified,Data(data.prefix(100)),Data("not a tar file".utf8)] {
            let candidate=temp.appendingPathComponent("candidate.tar.gz");try payload.write(to:candidate)
            XCTAssertThrowsError(try store.importPackage(from:candidate))
            XCTAssertFalse(FileManager.default.fileExists(atPath:root.path))
        }
    }
    func testFailedReplacementPreservesWorkingInstallation()throws {
        let store=RARInstallationStore(root:root)
        try store.importPackage(from:original())
        let invalid=try touch("wrong.tar.gz")
        XCTAssertThrowsError(try store.importPackage(from:invalid))
        XCTAssertEqual(try store.installedExecutable(),store.executable)
    }
    func testRepeatedImportCommitsCompleteInstallation()throws {
        let store=RARInstallationStore(root:root),source=try original()
        try store.importPackage(from:source);try store.importPackage(from:source)
        XCTAssertEqual(try store.installedExecutable(),store.executable)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),["current"])
    }
    func testCancellationPreservesExistingInstallation()throws {
        let store=RARInstallationStore(root:root),source=try original()
        try store.importPackage(from:source)
        let control=JobControl();control.cancel()
        XCTAssertThrowsError(try store.importPackage(from:source,control:control)) {XCTAssertEqual($0 as? ArchiveError,.cancelled)}
        XCTAssertEqual(try store.installedExecutable(),store.executable)
    }
    func testSymlinkAndHardLinkPackagesRejected()throws {
        let source=try original(),link=temp.appendingPathComponent("link.tar.gz"),store=RARInstallationStore(root:root)
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:source)
        XCTAssertThrowsError(try store.importPackage(from:link))
        let copy=temp.appendingPathComponent("copy.tar.gz"),hard=temp.appendingPathComponent("hard.tar.gz")
        try FileManager.default.copyItem(at:source,to:copy);try FileManager.default.linkItem(at:copy,to:hard)
        XCTAssertThrowsError(try store.importPackage(from:hard))
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.path))
    }
    func testSymlinkInstallationRootRejected()throws {
        try FileManager.default.createSymbolicLink(at:root,withDestinationURL:temp)
        XCTAssertThrowsError(try RARInstallationStore(root:root).importPackage(from:original()))
        XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent("current").path))
    }
    func testTamperedBinaryAndOriginalAreNotDiscovered()throws {
        let store=RARInstallationStore(root:root),source=try original()
        try store.importPackage(from:source)
        try Data("invalid binary".utf8).write(to:store.executable)
        XCTAssertThrowsError(try store.installedExecutable())
        try store.importPackage(from:source)
        try Data("invalid original".utf8).write(to:store.originalPackage)
        XCTAssertThrowsError(try store.installedExecutable())
    }
    func testManagedDiscoveryRequiresCustomerLicenseEvenInDevelopmentCLI()throws {
        let store=RARInstallationStore(root:root)
        try store.importPackage(from:original())
        // An explicit missing developer override suppresses any test-suite ARCORA_RAR override.
        let engines=EngineLocations.discover(rar:temp.appendingPathComponent("missing-rar"),rarEngineDirectory:root)
        XCTAssertEqual(engines.rar,store.executable)
        XCTAssertEqual(engines.rarInstallationDirectory,root)
        XCTAssertTrue(engines.rarRequiresLicense)
        XCTAssertFalse(engines.rarIsBundled)
        XCTAssertEqual(try engines.requireRAR(),store.executable)
        try Data("tampered".utf8).write(to:store.executable)
        XCTAssertThrowsError(try engines.requireRAR())
    }
    func testBrowserQuarantineIsPreservedNotStripped()throws {
        let source=temp.appendingPathComponent("download.tar.gz")
        try FileManager.default.copyItem(at:original(),to:source)
        let marker=Data("0081;12345678;ArcoraTest;".utf8)
        let set=marker.withUnsafeBytes{setxattr(source.path,"com.apple.quarantine",$0.baseAddress,$0.count,0,0)}
        XCTAssertEqual(set,0)
        let store=RARInstallationStore(root:root);try store.importPackage(from:source)
        for url in [source,store.originalPackage,store.executable] {
            var bytes=[UInt8](repeating:0,count:256)
            let count=getxattr(url.path,"com.apple.quarantine",&bytes,bytes.count,0,0)
            XCTAssertGreaterThan(count,0)
            if count>0 {XCTAssertEqual(Data(bytes.prefix(count)),marker)}
        }
    }
}
#endif
