import Foundation
import XCTest
@testable import ArcoraCore

/// These tests use the REAL pinned 7zz. They never substitute a mock codec.
/// Missing binaries are an explicit skip locally and a hard failure in release CI.
final class SevenZipIntegrationTests:ArcoraTestCase {
    private func service()throws->ArchiveService {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let engine=ProcessInfo.processInfo.environment["ARCORA_7ZZ"].map{URL(fileURLWithPath:$0)} ?? root.appendingPathComponent("Vendor/7zip/7zz")
        guard FileManager.default.isExecutableFile(atPath:engine.path) else {
            if ProcessInfo.processInfo.environment["ARCORA_REQUIRE_7ZZ"]=="1" {throw ArchiveError.missingEngine("CI requires the official pinned 7zz.")}
            throw XCTSkip("Official 7zz not available. Run Scripts/bootstrap-engines.sh, then rerun tests.")
        }
        var limits=SafetyLimits();limits.maxMemoryBytes=2_147_483_648;limits.timeout=45
        return ArchiveService(engines:EngineLocations(sevenZip:engine,worker:try worker()),limits:limits)
    }
    private func options(_ format:ArchiveFormat)->CompressionOptions {
        var value=CompressionOptions();value.format=format;value.threads=2;value.dictionaryMiB=8;value.level=format == .tar ? 0 : 5;return value
    }
    func testAllPrimaryWritersRoundTrip()throws {
        let service=try service()
        let file=try touch("input/资料_日本語.txt","中文・日本語・English\n")
        for format in ArchiveFormat.allCases where format != .rar {
            let result=try service.create(inputs:[file],in:temp,name:"archive-"+format.rawValue,options:options(format))
            XCTAssertEqual(result.outputs.count,1)
            let restored=try service.extract(result.outputs[0],to:temp,name:"restored-"+format.rawValue)
            let files=(FileManager.default.enumerator(at:restored.outputs[0],includingPropertiesForKeys:[.isRegularFileKey])?.allObjects as? [URL] ?? []).filter{(try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true}
            XCTAssertEqual(files.count,1,format.rawValue)
            if let restoredFile=files.first {XCTAssertEqual(try Data(contentsOf:restoredFile),try Data(contentsOf:file),format.rawValue)}
        }
    }
    func testEncrypted7zUnicodeAndZIPASCIIPasswords()throws {
        let service=try service(),file=try touch("data.txt","encrypted fixture")
        for format in [ArchiveFormat.sevenZip,.zip] {
            let password=try Secret(format == .zip ? "Arcora ASCII ! 123" : "data_密码_日本語_🔐")
            let result=try service.create(inputs:[file],in:temp,name:"protected-"+format.rawValue,options:options(format),password:password)
            let output=try service.extract(result.outputs[0],to:temp,name:"decrypted-"+format.rawValue,password:password)
            XCTAssertEqual(try String(contentsOf:output.outputs[0].appendingPathComponent("data.txt")),"encrypted fixture")
            XCTAssertThrowsError(try service.test(result.outputs[0],password:Secret("wrong-password")))
        }
    }
    func testUnsupportedZIPUnicodePasswordFailsBeforeCreation()throws {
        let service=try service(),file=try touch("data.txt","fixture")
        XCTAssertThrowsError(try service.create(inputs:[file],in:temp,name:"unicode",options:options(.zip),password:Secret("中文"))) {
            guard case .invalid = $0 as? ArchiveError else {return XCTFail("Expected explicit format constraint, got \($0)")}
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent("unicode.zip").path))
    }
    func testRealMultipartRoundTripAndMissingPart()throws {
        let service=try service(),file=try touch("blob.bin")
        try Data((0..<200_000).map{UInt8(truncatingIfNeeded:$0)}).write(to:file)
        for format in [ArchiveFormat.sevenZip,.zip] {
            var o=options(format);o.level=0;o.volumeBytes=65_536
            let result=try service.create(inputs:[file],in:temp,name:"split-"+format.rawValue,options:o)
            let parts=try FileManager.default.contentsOfDirectory(at:result.outputs[0],includingPropertiesForKeys:nil).sorted{$0.path<$1.path}
            XCTAssertGreaterThan(parts.count,2)
            let output=try service.extract(parts.last!,to:temp,name:"joined-"+format.rawValue)
            XCTAssertEqual(try Data(contentsOf:output.outputs[0].appendingPathComponent("blob.bin")),try Data(contentsOf:file))
            try FileManager.default.removeItem(at:parts[1])
            XCTAssertThrowsError(try service.inspect(parts.last!))
        }
    }
    func testOfficial7zReadsRealRAR5Fixtures()throws {
        let service=try service()
        for file in ["rar5-stored.rar","rar5-compressed.rar"] {
            let m=try service.inspect(fixture(file));XCTAssertEqual(m.backend,.sevenZip)
            _=try service.extract(fixture(file),to:temp,name:file+"-out")
        }
    }
    func testClassicRARAndEncryptedSolidRAR4Fixtures() throws {
        let service=try service()
        let old=fixture("rar4-windows.rar")
        XCTAssertEqual(try service.inspect(old).entries.count,5)
        let out=try service.extract(old,to:temp,name:"rar4-windows").outputs[0]
        XCTAssertEqual(try String(contentsOf:out.appendingPathComponent("test.txt")),"test text file\r\n")
        let encrypted=fixture("rar4-solid-encrypted.rar"),password=try Secret("password")
        XCTAssertThrowsError(try service.inspect(encrypted)) {XCTAssertEqual($0 as? ArchiveError,.passwordRequired)}
        _=try service.test(encrypted,password:password)
        let restored=try service.extract(encrypted,to:temp,name:"rar4-encrypted",password:password).outputs[0]
        for name in ["a.txt","b.txt","c.txt","d.txt"] {
            XCTAssertEqual(try String(contentsOf:restored.appendingPathComponent(name)),"This is from "+name)
        }
    }
    func testFolderCompressionIncludesDescendantsAndEmptyFiles()throws {
        let service=try service();_=try touch("folder/a.txt","a");_=try touch("folder/nested/b.txt","b");_=try touch("folder/empty","")
        let result=try service.create(inputs:[temp.appendingPathComponent("folder")],in:temp,name:"tree",options:options(.sevenZip))
        let output=try service.extract(result.outputs[0],to:temp,name:"tree-result")
        XCTAssertEqual(try String(contentsOf:output.outputs[0].appendingPathComponent("folder/nested/b.txt")),"b")
        XCTAssertTrue(FileManager.default.fileExists(atPath:output.outputs[0].appendingPathComponent("folder/empty").path))
    }
    func testLicensedRARAdapterRoundTrip()throws {
        guard let path=ProcessInfo.processInfo.environment["ARCORA_RAR"],FileManager.default.isExecutableFile(atPath:path) else {
            if ProcessInfo.processInfo.environment["ARCORA_REQUIRE_RAR"]=="1" {throw ArchiveError.missingEngine("RAR release tests require ARCORA_RAR.")}
            throw XCTSkip("Official RAR tool was not supplied (ARCORA_RAR).")
        }
        let base=try service(),service=ArchiveService(engines:EngineLocations(sevenZip:base.engines.sevenZip,worker:base.engines.worker,rar:URL(fileURLWithPath:path)),limits:base.limits)
        let file=try touch("input/日本語.txt","RAR source content"),password=try Secret("Arcora_密码123")
        let archive=try service.create(inputs:[file.deletingLastPathComponent()],in:temp,name:"licensed",options:options(.rar),password:password)
        let output=try service.extract(archive.outputs[0],to:temp,name:"rar-restored",password:password)
        XCTAssertEqual(try String(contentsOf:output.outputs[0].appendingPathComponent("input/日本語.txt")),"RAR source content")
    }
}
