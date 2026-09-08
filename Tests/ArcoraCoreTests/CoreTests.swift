import XCTest
import Foundation
@testable import ArcoraCore

class ArcoraTestCase:XCTestCase {
    var temp:URL!
    override func setUpWithError() throws {
        temp=FileManager.default.temporaryDirectory.appendingPathComponent("Arcora-tests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
    }
    override func tearDownWithError() throws { if let temp { try? FileManager.default.removeItem(at:temp) } }
    func fixture(_ name:String)->URL { Bundle.module.resourceURL!.appendingPathComponent("Fixtures/"+name) }
    func touch(_ name:String,_ value:String="data")throws->URL {
        let url=temp.appendingPathComponent(name)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data(value.utf8).write(to:url);return url
    }
    func worker()throws->URL {
        // Use the worker from this test configuration, never a stale Debug worker in Release tests.
        let bundle=Bundle(for:ArcoraTestCase.self).bundleURL
        let directory=bundle.pathExtension == "xctest" ? bundle.deletingLastPathComponent() : URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent()
        let candidates=[directory.appendingPathComponent("arcora-worker")]
        guard let url=candidates.first(where:{FileManager.default.isExecutableFile(atPath:$0.path)}) else {throw XCTSkip("Run swift build before worker integration tests.")};return url
    }
    func nativeService()throws->ArchiveService { ArchiveService(engines:EngineLocations(worker:try worker())) }
}
final class PathSafetyTests:ArcoraTestCase {
    func testUnicodeAndDots()throws { XCTAssertEqual(try PathSafety.canonicalEntry("./hello//世界.txt"),"hello/世界.txt") }
    func testRejectsTraversal() { for value in ["../x","a/../../b","/etc/passwd","C:/Windows/x","\\server\\x","a\\b","a\nb","a\rb"] { XCTAssertThrowsError(try PathSafety.canonicalEntry(value),value) } }
    func testEmbeddedNulRejected() { XCTAssertThrowsError(try PathSafety.canonicalEntry("safe\0/../x")) }
    func testRootDirectoryAllowed()throws { try PathSafety.validate([ArchiveEntry(path:"./",isDirectory:true)],limits:SafetyLimits()) }
    func testRootFileRejected() { XCTAssertThrowsError(try PathSafety.validate([ArchiveEntry(path:".")],limits:SafetyLimits())) }
    func testCaseCollision() { XCTAssertThrowsError(try PathSafety.validate([ArchiveEntry(path:"A.txt"),ArchiveEntry(path:"a.txt")],limits:SafetyLimits())) }
    func testNormalizationCollision() { XCTAssertThrowsError(try PathSafety.validate([ArchiveEntry(path:"café"),ArchiveEntry(path:"cafe\u{301}")],limits:SafetyLimits())) }
    func testParentConflictsRegardlessOfOrder() { for entries in [[ArchiveEntry(path:"a"),ArchiveEntry(path:"a/b")],[ArchiveEntry(path:"a/b"),ArchiveEntry(path:"a")]] { XCTAssertThrowsError(try PathSafety.validate(entries,limits:SafetyLimits())) } }
    func testLinkRejected() { XCTAssertThrowsError(try PathSafety.validate([ArchiveEntry(path:"a",linkTarget:"x")],limits:SafetyLimits())) }
    func testEntryQuota() { var limit=SafetyLimits();limit.maxEntries=1;XCTAssertThrowsError(try PathSafety.validate([ArchiveEntry(path:"a"),ArchiveEntry(path:"b")],limits:limit)) }
    func testExpandedQuotaAndOverflow() { var limit=SafetyLimits();limit.maxExpandedBytes=UInt64.max;XCTAssertThrowsError(try PathSafety.validate([ArchiveEntry(path:"a",size:UInt64.max),ArchiveEntry(path:"b",size:1)],limits:limit)) }
    func testContainsUsesPathBoundary() { XCTAssertFalse(PathSafety.contains(URL(fileURLWithPath:"/foo"),URL(fileURLWithPath:"/foobar/x"))); XCTAssertTrue(PathSafety.contains(URL(fileURLWithPath:"/foo"),URL(fileURLWithPath:"/foo/x"))) }
    func testUnsafeFileNames() { for name in ["",".","..","a/b","a:b","a\0b",String(repeating:"x",count:181)] { XCTAssertThrowsError(try PathSafety.safeFilename(name),name) } }
    func testOutputInsideInputRejected()throws {
        _=try touch("folder/data.txt");let dir=temp.appendingPathComponent("folder")
        XCTAssertThrowsError(try PathSafety.validateInputs([dir],outputParent:dir,limits:SafetyLimits(),control:JobControl()))
    }
    func testCompressionInputSymlinkRejected()throws {
        let original=try touch("original"),link=temp.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:original)
        XCTAssertThrowsError(try PathSafety.validateInputs([link],outputParent:temp,limits:SafetyLimits(),control:JobControl()))
    }
    func testOutputAuditRejectsSymlinks()throws {
        let root=temp.appendingPathComponent("result");try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("link"),withDestinationURL:URL(fileURLWithPath:"/tmp"))
        XCTAssertThrowsError(try PathSafety.auditOutput(root,limits:SafetyLimits(),control:JobControl()))
    }
}
final class SecretAndArgumentsTests:ArcoraTestCase {
    func testSecretCopiesAreIndependent()throws {let a=try Secret("密码🔐日本語"),b=a.copy();a.clear();XCTAssertEqual(b.withBytes{String(decoding:$0,as:UTF8.self)},"密码🔐日本語");b.clear();XCTAssertTrue(b.withBytes{$0.isEmpty})}
    func testSecretValidation() {for s in ["","a\nb","a\0b",String(repeating:"x",count:1025)] {XCTAssertThrowsError(try Secret(s))}}
    func testPasswordIsNeverInArguments()throws {let options=CompressionOptions();let args=SevenZipArguments.create(temp.appendingPathComponent("out.7z"),list:temp.appendingPathComponent("list"),options:options,password:true);XCTAssertTrue(args.contains("-p"));XCTAssertTrue(args.contains("-mhe=on"));XCTAssertEqual(args.filter{$0.hasPrefix("-p")},["-p"])}
    func test7zParameters() {var o=CompressionOptions();o.threads=6;o.dictionaryMiB=64;o.level=7;o.volumeBytes=100*1_048_576;let a=SevenZipArguments.create(temp,list:temp,options:o,password:true);for flag in ["-mmt=6","-md=64m","-mx=7","-v104857600b","-spd","--"] {XCTAssertTrue(a.contains(flag),flag)}}
    func testStoreReallyUsesCopy() {var o=CompressionOptions();o.level=0;XCTAssertTrue(SevenZipArguments.create(temp,list:temp,options:o,password:false).contains("-m0=Copy"));o.format = .zip;XCTAssertTrue(SevenZipArguments.create(temp,list:temp,options:o,password:false).contains("-mm=Copy"))}
    func testZipEncryptionAndNoHeaderSwitch() {var o=CompressionOptions();o.format = .zip;let a=SevenZipArguments.create(temp,list:temp,options:o,password:true);XCTAssertTrue(a.contains("-mem=AES256"));XCTAssertFalse(a.contains(where:{$0.hasPrefix("-mhe")}))}
    func testRARUsesStdinSwitchAndUTF8List() {var o=CompressionOptions();o.format = .rar;let a=RARArguments.create(temp,list:temp,options:o,password:true);XCTAssertTrue(a.contains("-hp"));XCTAssertTrue(a.contains("-scfl"));XCTAssertTrue(a.contains("-cfg-"));XCTAssertTrue(a.contains("--"))}
    func testInvalidOptions() {var o=CompressionOptions();o.threads=0;XCTAssertThrowsError(try o.validate(hasPassword:false));o.threads=1;o.level=2;XCTAssertThrowsError(try o.validate(hasPassword:false));o.level=5;o.dictionaryMiB=3;XCTAssertThrowsError(try o.validate(hasPassword:false))}
    func testUnsupportedEncryptionAndSplits() {var o=CompressionOptions();o.format = .tar;XCTAssertThrowsError(try o.validate(hasPassword:true));o.volumeBytes=65536;XCTAssertThrowsError(try o.validate(hasPassword:false))}
    func testMemoryGrowsWithDictionaryAndThreads() {var a=CompressionOptions();a.threads=2;var b=a;b.dictionaryMiB=64;XCTAssertGreaterThan(b.estimatedMemoryBytes,a.estimatedMemoryBytes);b.threads=8;XCTAssertGreaterThan(b.estimatedMemoryBytes,a.estimatedMemoryBytes)}
    func testWarningIsNotSuccess() {XCTAssertThrowsError(try ProcessRunner.requireSuccess(ProcessResult(status:1,output:"Warning: file skipped"),passwordSupplied:false))}
    func testWrongPasswordClassification() {XCTAssertThrowsError(try ProcessRunner.requireSuccess(ProcessResult(status:2,output:"Wrong password"),passwordSupplied:true)){XCTAssertEqual($0 as? ArchiveError,.wrongPassword)}}
}
final class MetadataTests:ArcoraTestCase {
    func testSLTUnicodeDirectoryPassword()throws {
        let text="Path = 资料\nFolder = +\nSize = 0\n\nPath = 资料/日本語.txt\nSize = 42\nPacked Size = 12\nEncrypted = +\nModified = 2023-11-14 22:13:20.0000000\n\n"
        let e=try SLTParser.parse(text);XCTAssertEqual(e.count,2);XCTAssertTrue(e[0].isDirectory);XCTAssertEqual(e[1].size,42);XCTAssertTrue(e[1].isEncrypted);XCTAssertNotNil(e[1].modified)
    }
    func testSLTRejectsForgedRecords() {for s in ["Path = safe\nPath = forged\nSize = 1\n","Path = name\nunstructured\nSize = 1\n","Path = ../escape\nSize = 1\n"] {XCTAssertThrowsError(try SLTParser.parse(s))}}
    func testSLTUnsafeLinkFlag()throws {let e=try SLTParser.parse("Path = link\nSize = 1\nSymbolic Link = ../../x\n");XCTAssertTrue(e[0].isUnsafeType)}
    func testSLTRejectsHugeSize() {XCTAssertThrowsError(try SLTParser.parse("Path = x\nSize = 999999999999999999999999\n"))}
    func testFramerPreservesSplitUnicode() {let frame=LineFramer();let data=Data("日本語\r42%\n".utf8);var lines=[String]();for byte in data {frame.consume(Data([byte])){lines.append($0)}};frame.finish{lines.append($0)};XCTAssertEqual(lines,["日本語","42%"])}
    func testManifestOverflowSaturates() {XCTAssertEqual(ArchiveManifest(source:temp,backend:.sevenZip,entries:[ArchiveEntry(path:"a",size:UInt64.max),ArchiveEntry(path:"b",size:3)],format:"test").totalBytes,UInt64.max)}
}
final class VolumeAndTransactionTests:ArcoraTestCase {
    func testNumberedPartResolvesFirst()throws {let first=try touch("a.7z.001");_=try touch("a.7z.002");let third=try touch("a.7z.003");let result=try VolumeResolver.resolve(third);XCTAssertEqual(result.first,first);XCTAssertEqual(result.parts.count,3)}
    func testNumberedGapRejected()throws {_=try touch("a.7z.001");let third=try touch("a.7z.003");XCTAssertThrowsError(try VolumeResolver.resolve(third))}
    func testRarPartWidthPreserved()throws {let first=try touch("a.part001.rar");let second=try touch("a.part002.rar");XCTAssertEqual(try VolumeResolver.resolve(second).first,first)}
    func testLegacyRARStartsAtRAR()throws {let first=try touch("a.rar");let part=try touch("a.r00");XCTAssertEqual(try VolumeResolver.resolve(part).first,first)}
    func testTraditionalSplitZIPStartsAtZIP()throws {let first=try touch("a.zip");let part=try touch("a.z01");XCTAssertEqual(try VolumeResolver.resolve(part).first,first)}
    func testVolumeSizeParsing()throws {XCTAssertEqual(try VolumeResolver.parseSize("100 MiB"),104857600);XCTAssertEqual(try VolumeResolver.parseSize("2 GiB"),2147483648);XCTAssertNil(try VolumeResolver.parseSize(""));XCTAssertThrowsError(try VolumeResolver.parseSize("2 k"));XCTAssertThrowsError(try VolumeResolver.parseSize("99999999999999999999999 GiB"))}
    func testFolderName() {XCTAssertEqual(ArchiveService.defaultFolderName(URL(fileURLWithPath:"/a/archive.tar.gz")),"archive");XCTAssertEqual(ArchiveService.defaultFolderName(URL(fileURLWithPath:"/a/photos.part003.rar")),"photos");XCTAssertEqual(ArchiveService.defaultFolderName(URL(fileURLWithPath:"/a/docs.7z.001")),"docs")}
    func testWorkspaceCleanup()throws {var area:Workspace?=try Workspace(parent:temp);let path=area!.payload.deletingLastPathComponent();XCTAssertTrue(FileManager.default.fileExists(atPath:path.path));area=nil;XCTAssertFalse(FileManager.default.fileExists(atPath:path.path))}
    func testAtomicCollisionDoesNotOverwrite()throws {let existing=try touch("result.txt","original");let area=try Workspace(parent:temp);let candidate=area.payload.appendingPathComponent("value");try Data("new".utf8).write(to:candidate);XCTAssertThrowsError(try area.commit(candidate,to:existing,policy:.fail));XCTAssertEqual(try String(contentsOf:existing),"original");let final=try area.commit(candidate,to:existing,policy:.rename);XCTAssertNotEqual(final,existing);XCTAssertEqual(try String(contentsOf:final),"new")}
    func testCommonParentWithSeparateDirectories() {XCTAssertEqual(ArchiveService.commonParent([URL(fileURLWithPath:"/data/a/x"),URL(fileURLWithPath:"/data/b/y")]).path,"/data")}
}
final class NativeIntegrationTests:ArcoraTestCase {
    func testZIPAndTARFiltersListAndExtract()throws {
        for name in ["normal.zip","normal.tar","normal.tar.gz","normal.tar.bz2","normal.tar.xz"] {
            let source=fixture(name),entries=try NativeArchive.list(source)
            XCTAssertEqual(entries.filter{!$0.isDirectory}.count,4,name)
            let dest=temp.appendingPathComponent(name+"-out");try FileManager.default.createDirectory(at:dest,withIntermediateDirectories:true)
            try NativeArchive.read(source,to:dest)
            XCTAssertEqual(try String(contentsOf:dest.appendingPathComponent("资料/日本語.txt")),"中文・日本語・English\n",name)
            XCTAssertEqual(try Data(contentsOf:dest.appendingPathComponent("nested/deep/value.bin")).count,1024)
            try NativeArchive.read(source,to:nil)
        }
    }
    func testSelectedExtraction()throws {try NativeArchive.read(fixture("normal.tar.gz"),to:temp,selection:["资料"]);XCTAssertTrue(FileManager.default.fileExists(atPath:temp.appendingPathComponent("资料/日本語.txt").path));XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent("hello.txt").path))}
    func testNativeUnsafePathsAndLinksRefused() {for name in ["traversal.zip","absolute.tar","symlink.tar","hardlink.tar","fifo.tar"] {XCTAssertThrowsError(try NativeArchive.read(fixture(name),to:temp),name)}}
    func testNativeExpansionBudgetDuringRead() {var limits=SafetyLimits();limits.maxExpandedBytes=1024;XCTAssertThrowsError(try NativeArchive.read(fixture("expansion-limit.zip"),to:temp,limits:limits));let size=(try? temp.appendingPathComponent("large.txt").resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0;XCTAssertLessThanOrEqual(size,1024)}
    func testNativeInvalidAndTruncatedArchivesFail() {for name in ["invalid.bin","truncated.tar"] {XCTAssertThrowsError(try NativeArchive.read(fixture(name),to:nil),name)}}
    func testAlreadyCancelledNeverExtracts() {let c=JobControl();c.cancel();XCTAssertThrowsError(try NativeArchive.read(fixture("normal.tar"),to:temp,control:c));XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent("hello.txt").path))}
    func testWorkerJSONAndServiceRoundTrip()throws {
        let service=try nativeService(),source=fixture("normal.tar.gz")
        let manifest=try service.inspect(source);XCTAssertEqual(manifest.backend,.libarchive);XCTAssertEqual(manifest.entries.count,4)
        let result=try service.extract(source,to:temp,name:"Restored");XCTAssertEqual(result.entries,7); // Four files plus three implicit directories.
        XCTAssertEqual(try String(contentsOf:result.outputs[0].appendingPathComponent("hello.txt")),"Hello from Arcora.\n")
        _=try service.test(source)
    }
    func testWorkerSelectedExtraction()throws {let r=try nativeService().extract(fixture("normal.zip"),to:temp,name:"Selected",selection:["hello.txt"]);XCTAssertTrue(FileManager.default.fileExists(atPath:r.outputs[0].appendingPathComponent("hello.txt").path));XCTAssertFalse(FileManager.default.fileExists(atPath:r.outputs[0].appendingPathComponent("资料").path))}
    func testCaseCollisionFailsBeforeOutputCommit()throws {XCTAssertThrowsError(try nativeService().extract(fixture("case-collision.zip"),to:temp,name:"Unsafe"));XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent("Unsafe").path));let children=try FileManager.default.contentsOfDirectory(atPath:temp.path);XCTAssertFalse(children.contains(where:{$0.hasPrefix(".arcora-")}))}
    func testSourceArchiveIsNeverChanged()throws {let source=try touch("source.zip");try Data(contentsOf:fixture("normal.zip")).write(to:source);let before=try Data(contentsOf:source);_=try nativeService().extract(source,to:temp,name:"source");XCTAssertEqual(try Data(contentsOf:source),before)}
}

final class ProcessExecutionTests:ArcoraTestCase {
    private func python()throws->URL {
        let candidates=["/usr/bin/python3","/usr/local/bin/python3","/opt/homebrew/bin/python3"]
        guard let path=candidates.first(where:{FileManager.default.isExecutableFile(atPath:$0)}) else {throw XCTSkip("Python 3 is needed for process protocol tests.")}
        return URL(fileURLWithPath:path)
    }
    func testDrainsBothPipesAndBoundsCapture()throws {
        let code="import os; os.write(1,b'A'*2000000); os.write(2,b'B'*2000000)"
        let r=try ProcessRunner().run(EngineCommand(try python(),["-c",code]),outputLimit:8192)
        XCTAssertEqual(r.status,0);XCTAssertLessThanOrEqual(r.output.utf8.count,8192);XCTAssertTrue(r.output.contains("B"))
    }
    func testFullCaptureFailsClosedAtLimit()throws {
        XCTAssertThrowsError(try ProcessRunner().run(EngineCommand(try python(),["-c","import os; os.write(1,b'A'*1000000)"]),outputLimit:4096,captureAll:true)) {guard case ArchiveError.resourceLimit = $0 else {return XCTFail("Unexpected: \($0)")}}
    }
    func testPasswordStdinAndRedaction()throws {
        let secret=try Secret("密码_日本語"),code="import sys; s=sys.stdin.readline().strip(); print(s); print('received' if len(s)>0 else 'missing')"
        let r=try ProcessRunner().run(EngineCommand(try python(),["-c",code],secret:secret,passwordCopies:1))
        XCTAssertEqual(r.status,0);XCTAssertTrue(r.output.contains("received"));XCTAssertTrue(r.output.contains("<redacted>"));XCTAssertFalse(r.output.contains("密码"))
    }
    func testClosingStdinWithoutPasswordNeverPromptsForever()throws {
        let r=try ProcessRunner().run(EngineCommand(try python(),["-c","import sys; print('EOF' if sys.stdin.read()=='' else 'data')"]))
        XCTAssertTrue(r.output.contains("EOF"))
    }
    func testTimeoutTerminatesProcess()throws {
        let begin=Date()
        XCTAssertThrowsError(try ProcessRunner().run(EngineCommand(try python(),["-c","import time; time.sleep(30)"]),timeout:0.1)) {XCTAssertEqual($0 as? ArchiveError,.timedOut)}
        XCTAssertLessThan(Date().timeIntervalSince(begin),5)
    }
    func testCancellationTerminatesProcess()throws {
        let control=JobControl();DispatchQueue.global().asyncAfter(deadline:.now()+0.15){control.cancel()}
        XCTAssertThrowsError(try ProcessRunner().run(EngineCommand(try python(),["-c","import time; time.sleep(30)"]),control:control)){XCTAssertEqual($0 as? ArchiveError,.cancelled)}
    }
    func testPauseResumeAndCancelAreConsistent()throws {
        let control=JobControl();control.pause();XCTAssertTrue(control.isPaused);control.resume();XCTAssertFalse(control.isPaused);control.cancel();XCTAssertThrowsError(try control.waitWhilePaused()){XCTAssertEqual($0 as? ArchiveError,.cancelled)}
    }
    func testEnvironmentDoesNotLeakInjectedLibraries()throws {
        let r=try ProcessRunner().run(EngineCommand(try python(),["-c","import os; print(os.environ.get('LD_PRELOAD','clean')); print(os.environ.get('DYLD_INSERT_LIBRARIES','clean'))"]))
        XCTAssertEqual(r.output.trimmingCharacters(in:.whitespacesAndNewlines),"clean\nclean")
    }
}

final class RARFixtureTests:ArcoraTestCase {
    func testRealRAR5StoredArchive()throws {
        let e=try NativeArchive.list(fixture("rar5-stored.rar"));XCTAssertEqual(e.first?.path,"helloworld.txt")
        try NativeArchive.read(fixture("rar5-stored.rar"),to:temp)
        XCTAssertEqual(try String(contentsOf:temp.appendingPathComponent("helloworld.txt")),"hello libarchive test suite!\n")
    }
    func testRealRAR5CompressedArchive()throws {
        try NativeArchive.read(fixture("rar5-compressed.rar"),to:temp)
        let actual=try Data(contentsOf:temp.appendingPathComponent("test.bin"))
        var expected=Data()
        for k in 1...300 {var value=UInt32(max(0,k*k-3*k+1)).littleEndian; withUnsafeBytes(of:&value){expected.append(contentsOf:$0)}}
        XCTAssertEqual(actual,expected)
    }
    func testSuccessfulMetadataPreservesPasswordLikeNames()throws {
        guard FileManager.default.isExecutableFile(atPath:"/usr/bin/python3") else {throw XCTSkip("Python needed")}
        let r=try ProcessRunner().run(EngineCommand(URL(fileURLWithPath:"/usr/bin/python3"),["-c","print('Path = secret.txt')"],secret:try Secret("secret")),captureAll:true)
        XCTAssertTrue(r.output.contains("secret.txt"))
    }
}
