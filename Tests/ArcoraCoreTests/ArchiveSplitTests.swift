import Foundation
import XCTest
@testable import ArcoraCore

final class ArchiveSplitTests:ArcoraTestCase {
    func testSplitReassemblesExactOriginalAndPreservesSource()throws {
        let source=try touch("archive.zip")
        let data=Data((0..<170_000).map{UInt8(truncatingIfNeeded:$0)})
        try data.write(to:source)
        let result=try ArchiveService(engines:EngineLocations()).split(source,to:temp,partBytes:65_536)
        let parts=try FileManager.default.contentsOfDirectory(at:result.outputs[0],includingPropertiesForKeys:nil).sorted{$0.path<$1.path}
        XCTAssertEqual(parts.count,3)
        var joined=Data()
        for part in parts {let data=try Data(contentsOf:part);XCTAssertLessThanOrEqual(data.count,65_536);joined.append(data)}
        XCTAssertEqual(joined,data)
        XCTAssertEqual(try Data(contentsOf:source),data)
        XCTAssertEqual(result.bytes,UInt64(data.count))
        XCTAssertEqual(parts[0].lastPathComponent,"archive.zip.001")
    }
    func testSplitCancellationLimitsAndCollisionPublishNoPartialSet()throws {
        let source=try touch("archive.zip")
        try Data(repeating:1,count:140_000).write(to:source)
        let service=ArchiveService(engines:EngineLocations()),control=JobControl()
        control.cancel()
        XCTAssertThrowsError(try service.split(source,to:temp,partBytes:65_536,control:control))
        XCTAssertThrowsError(try service.split(source,to:temp,partBytes:1))
        let output=try service.split(source,to:temp,partBytes:65_536).outputs[0]
        let before=try Data(contentsOf:output.appendingPathComponent("archive.zip.001"))
        XCTAssertThrowsError(try service.split(source,to:temp,partBytes:65_536,collision:.fail))
        XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent("archive.zip.001")),before)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:temp.path).contains{$0.hasPrefix(".arcora-")})
    }
    func testCancellationDuringCopyCleansAllUncommittedParts()throws {
        let source=try touch("cancel.zip")
        let original=Data(repeating:7,count:170_000)
        try original.write(to:source)
        let control=JobControl(),service=ArchiveService(engines:EngineLocations())
        XCTAssertThrowsError(try service.split(source,to:temp,partBytes:65_536,control:control,progress:{_ in control.cancel()})) {
            XCTAssertEqual($0 as? ArchiveError,.cancelled)
        }
        XCTAssertEqual(try Data(contentsOf:source),original)
        XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent("cancel.zip.parts").path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:temp.path).contains{$0.hasPrefix(".arcora-")})
    }
}
