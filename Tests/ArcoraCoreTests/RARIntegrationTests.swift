import Foundation
import XCTest
@testable import ArcoraCore

/// Real official RAR -> 7-Zip interoperability. No mocked archive formats.
final class RARIntegrationTests:ArcoraTestCase {
    private func service() throws -> ArchiveService {
        // Codec tests opt in through ARCORA_RAR, never through a developer's
        // imported app engine or license state in Application Support.
        let engines=EngineLocations.discover(rarEngineDirectory:temp.appendingPathComponent("managed-rar"))
        guard engines.rar != nil,engines.sevenZip != nil else {
            if ProcessInfo.processInfo.environment["ARCORA_REQUIRE_RAR"]=="1" {
                throw ArchiveError.missingEngine("RAR tests require ARCORA_RAR and the pinned 7zz.")
            }
            throw XCTSkip("Set ARCORA_RAR to an official RAR executable for integration testing.")
        }
        var limits=SafetyLimits();limits.timeout=45;limits.maxMemoryBytes=2_147_483_648
        return ArchiveService(engines:engines,limits:limits)
    }
    private func options() -> CompressionOptions {
        var value=CompressionOptions();value.format = .rar;value.dictionaryMiB=4;value.threads=2
        return value
    }
    private func tree() throws -> URL {
        _=try touch("资料 日本語/中文🔐.txt","中文、日本語, English\n")
        _=try touch("资料 日本語/nested/.hidden","hidden")
        _=try touch("资料 日本語/nested/-switch.txt","dash")
        _=try touch("资料 日本語/nested/@file.txt","at")
        _=try touch("资料 日本語/empty.txt","")
        try FileManager.default.createDirectory(at:temp.appendingPathComponent("资料 日本語/empty folder"),withIntermediateDirectories:true)
        return temp.appendingPathComponent("资料 日本語")
    }
    private func assertTree(_ root:URL) throws {
        XCTAssertEqual(try String(contentsOf:root.appendingPathComponent("资料 日本語/中文🔐.txt")),"中文、日本語, English\n")
        XCTAssertEqual(try String(contentsOf:root.appendingPathComponent("资料 日本語/nested/.hidden")),"hidden")
        XCTAssertEqual(try String(contentsOf:root.appendingPathComponent("资料 日本語/nested/-switch.txt")),"dash")
        XCTAssertEqual(try String(contentsOf:root.appendingPathComponent("资料 日本語/nested/@file.txt")),"at")
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("资料 日本語/empty.txt")).count,0)
        XCTAssertEqual(try root.appendingPathComponent("资料 日本語/empty folder").resourceValues(forKeys:[.isDirectoryKey]).isDirectory,true)
    }
    func testAllLevelsSolidAndNonSolidRoundTrip() throws {
        let service=try service(),input=try tree()
        for solid in [false,true] {
            for level in ArchiveFormat.rar.levels {
                var o=options();o.solid=solid;o.level=level
                let label="level-\(level)-\(solid)"
                let archive=try service.create(inputs:[input],in:temp,name:label,options:o).outputs[0]
                // Require a real RAR5 signature, not a renamed ZIP.
                XCTAssertEqual(Array(try Data(contentsOf:archive).prefix(8)),[0x52,0x61,0x72,0x21,0x1a,0x07,0x01,0x00])
                _=try service.test(archive)
                try assertTree(service.extract(archive,to:temp,name:label+"-out").outputs[0])
            }
        }
    }
    func testUnicodePasswordsWithAndWithoutEncryptedNames() throws {
        let service=try service(),input=try tree(),password=try Secret("空 格_日本語_🔐_123")
        for encryptedNames in [false,true] {
            var o=options();o.encryptHeaders=encryptedNames
            let archive=try service.create(inputs:[input],in:temp,name:"encrypted-\(encryptedNames)",options:o,password:password).outputs[0]
            if encryptedNames {
                XCTAssertThrowsError(try service.inspect(archive)) {XCTAssertEqual($0 as? ArchiveError,.passwordRequired)}
            } else {XCTAssertTrue(try service.inspect(archive).encrypted)}
            XCTAssertThrowsError(try service.extract(archive,to:temp,name:"wrong-password",password:Secret("incorrect"))) {XCTAssertEqual($0 as? ArchiveError,.wrongPassword)}
            XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent("wrong-password").path))
            try assertTree(service.extract(archive,to:temp,name:"decrypted-\(encryptedNames)",password:password).outputs[0])
        }
    }
    func testSelectedDirectoryDoesNotExtractSiblings() throws {
        let service=try service(),input=try tree()
        let archive=try service.create(inputs:[input],in:temp,name:"selected",options:options()).outputs[0]
        let out=try service.extract(archive,to:temp,name:"selected-out",selection:["资料 日本語/nested"]).outputs[0]
        XCTAssertEqual(try String(contentsOf:out.appendingPathComponent("资料 日本語/nested/@file.txt")),"at")
        XCTAssertFalse(FileManager.default.fileExists(atPath:out.appendingPathComponent("资料 日本語/中文🔐.txt").path))
    }
    func testEncryptedVolumesOpenFromMiddleAndRejectMissingParts() throws {
        let service=try service(),file=try touch("data.bin"),password=try Secret("分卷_secret")
        let data=Data((0..<210_000).map{UInt8(truncatingIfNeeded:$0)})
        try data.write(to:file)
        var o=options();o.level=0;o.volumeBytes=65_536
        let folder=try service.create(inputs:[file],in:temp,name:"split",options:o,password:password).outputs[0]
        let parts=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).sorted{$0.path<$1.path}
        XCTAssertGreaterThan(parts.count,2)
        let out=try service.extract(parts[1],to:temp,name:"joined",password:password).outputs[0]
        XCTAssertEqual(try Data(contentsOf:out.appendingPathComponent("data.bin")),data)
        let last=parts.last!,lastData=try Data(contentsOf:last)
        try FileManager.default.removeItem(at:last)
        XCTAssertThrowsError(try service.extract(parts[0],to:temp,name:"missing-last",password:password))
        XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent("missing-last").path))
        try lastData.write(to:last)
        try FileManager.default.removeItem(at:parts[1])
        XCTAssertThrowsError(try service.inspect(last,password:password))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:temp.path).contains{$0.hasPrefix(".arcora-")})
    }
    func testCorruptedArchiveIsNotCommitted() throws {
        let service=try service(),file=try touch("blob.bin",String(repeating:"testing data",count:10_000))
        var o=options();o.level=0
        let archive=try service.create(inputs:[file],in:temp,name:"damaged",options:o).outputs[0]
        var data=try Data(contentsOf:archive);data[data.count/2] ^= 0xff;try data.write(to:archive)
        XCTAssertThrowsError(try service.extract(archive,to:temp,name:"damaged-out"))
        XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent("damaged-out").path))
    }
    func testCreationCollisionAndCancellationPreserveOriginals() throws {
        let service=try service(),input=try tree()
        let archive=try service.create(inputs:[input],in:temp,name:"same",options:options()).outputs[0]
        let original=try Data(contentsOf:archive)
        XCTAssertThrowsError(try service.create(inputs:[input],in:temp,name:"same",options:options(),collision:.fail))
        XCTAssertEqual(try Data(contentsOf:archive),original)
        let control=JobControl()
        XCTAssertThrowsError(try service.create(inputs:[input],in:temp,name:"cancelled",options:options(),control:control,progress:{event in
            if event.phase=="phase.compressing" {control.cancel()}
        })) {XCTAssertEqual($0 as? ArchiveError,.cancelled)}
        XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent("cancelled.rar").path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:temp.path).contains{$0.hasPrefix(".arcora-")})
    }
    func testExplicitUnusualFilenames() throws {
        let service=try service()
        for name in ["two words.txt","-switch.txt","@literal.txt","quote\".txt","trailing space "] {
            let file=try touch("names/"+name,"filename content")
            let archive=try service.create(inputs:[file],in:temp,name:"name-test",options:options()).outputs[0]
            let out=try service.extract(archive,to:temp,name:"name-out").outputs[0]
            XCTAssertEqual(try String(contentsOf:out.appendingPathComponent(name)),"filename content")
        }
    }
    func testChangedSourceIsNotPublishedAsComplete() throws {
        let service=try service(),file=try touch("changing.txt","before")
        XCTAssertThrowsError(try service.create(inputs:[file],in:temp,name:"changed",options:options(),progress:{event in
            if event.phase=="phase.compressing" {try? Data("changed source content".utf8).write(to:file)}
        }))
        XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent("changed.rar").path))
    }
}

final class RARDiscoveryAndVolumeTests:ArcoraTestCase {
    func testBundledRARNeedsNoSavedPreference() throws {
        let app=temp.appendingPathComponent("Example.app")
        #if arch(arm64)
        let arch="arm64"
        #else
        let arch="x86_64"
        #endif
        for path in ["7zz","arcora-worker","rar/"+arch+"/rar"] {
            let file=try touch("Example.app/Contents/Helpers/"+path,"")
            try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:file.path)
        }
        _=try touch("Example.app/Contents/Info.plist","<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>test.arcora</string></dict></plist>")
        let bundle=try XCTUnwrap(Bundle(url:app))
        let engines=EngineLocations.discover(bundle:bundle,rar:URL(fileURLWithPath:"/missing/stale/rar"),
            rarEngineDirectory:temp.appendingPathComponent("managed-rar"))
        XCTAssertTrue(engines.rarIsBundled)
        XCTAssertEqual(engines.rar?.lastPathComponent,"rar")
        XCTAssertTrue(engines.rar?.path.contains("Contents/Helpers/rar/")==true)
        XCTAssertNotNil(engines.sevenZip)
    }
    func testClassicVolumeSequenceContinuesBeyondR99() throws {
        let first=try touch("old.rar")
        for n in 0...99 {_=try touch(String(format:"old.r%02d",n))}
        let last=try touch("old.s00")
        let volumes=try VolumeResolver.resolve(last)
        XCTAssertEqual(volumes.first,first)
        XCTAssertEqual(volumes.parts.count,102)
        try FileManager.default.removeItem(at:temp.appendingPathComponent("old.r99"))
        XCTAssertThrowsError(try VolumeResolver.resolve(last))
    }
    func testEmptyRARLinkMetadataDoesNotMarkRegularFilesAsLinks() throws {
        let entries=try SLTParser.parse("Path = plain.txt\nSize = 1\nSymbolic Link = \nHard Link = \n\n")
        XCTAssertEqual(entries.count,1)
        XCTAssertFalse(entries[0].isUnsafeType)
        try PathSafety.validate(entries,limits:SafetyLimits())
    }
}
