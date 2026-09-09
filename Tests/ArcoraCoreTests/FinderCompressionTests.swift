import Foundation
import XCTest
@testable import ArcoraCore
#if os(macOS)
import AppKit
#endif

final class FinderCompressionTests:ArcoraTestCase {
    func testRequestRejectsEmptyRemoteAndOversizedSelections()throws {
        XCTAssertThrowsError(try FinderCompressionRequest(files:[],action:.zip))
        XCTAssertThrowsError(try FinderCompressionRequest(files:[URL(string:"https://example.com/data")!],action:.zip))
        XCTAssertThrowsError(try FinderCompressionRequest(files:[URL(string:"file://remote-host/share/file")!],action:.zip))
        XCTAssertThrowsError(try FinderCompressionRequest(files:Array(repeating:temp,count:10_001),action:.zip))
    }
    func testRequestSnapshotsDeduplicatesAndRejectsControlCharacters()throws {
        let file=try touch("中文 日本語.txt")
        let request=try FinderCompressionRequest(files:[file,file],action:.sevenZip)
        XCTAssertEqual(request.files,[file]);XCTAssertEqual(request.action.format,.sevenZip)
        XCTAssertThrowsError(try FinderCompressionRequest(files:[temp.appendingPathComponent("bad\nname")],action:.zip))
    }
    func testSingleFileDefaultsBesideOriginal()throws {
        let file=try touch("资料 日本語.txt")
        let plan=try FinderCompressionPlan(request:FinderCompressionRequest(files:[file],action:.zip))
        XCTAssertEqual(plan.name,"资料 日本語")
        XCTAssertEqual(plan.siblingDirectory,try PathSafety.physicalURL(temp))
        XCTAssertEqual(try String(contentsOf:file),"data")
    }
    func testFolderWithDotsKeepsItsCompleteName()throws {
        _=try touch("项目.v1/data.txt")
        let folder=temp.appendingPathComponent("项目.v1")
        let plan=try FinderCompressionPlan(request:FinderCompressionRequest(files:[folder],action:.rar))
        XCTAssertEqual(plan.name,"项目.v1")
        XCTAssertEqual(plan.siblingDirectory,try PathSafety.physicalURL(temp))
    }
    func testNestedSelectionDoesNotDuplicateFolderContents()throws {
        let file=try touch("folder/data.txt"),folder=temp.appendingPathComponent("folder")
        let plan=try FinderCompressionPlan(request:FinderCompressionRequest(files:[file,folder,file],action:.zip))
        XCTAssertEqual(plan.files,[try PathSafety.physicalURL(folder)])
    }
    func testMultipleSiblingsUseTheirParentName()throws {
        let first=try touch("组合/a.txt"),second=try touch("组合/b.txt")
        let plan=try FinderCompressionPlan(request:FinderCompressionRequest(files:[first,second],action:.zip))
        XCTAssertEqual(plan.name,"组合");XCTAssertEqual(plan.files.count,2)
        XCTAssertEqual(plan.siblingDirectory,try PathSafety.physicalURL(first.deletingLastPathComponent()))
    }
    func testDifferentLocationsRequireExplicitDestination()throws {
        let first=try touch("first/a.txt"),second=try touch("second/b.txt")
        let plan=try FinderCompressionPlan(request:FinderCompressionRequest(files:[first,second],action:.zip))
        XCTAssertNil(plan.siblingDirectory);XCTAssertEqual(plan.name,"Archive")
    }
    func testMissingInputAndSymlinkAreRejected()throws {
        XCTAssertThrowsError(try FinderCompressionPlan(request:FinderCompressionRequest(files:[temp.appendingPathComponent("missing")],action:.zip)))
        let file=try touch("real.txt"),link=temp.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:file)
        XCTAssertThrowsError(try FinderCompressionPlan(request:FinderCompressionRequest(files:[link],action:.zip)))
    }
    func testLongInputNameUsesSafeFallbackWithoutChangingInput()throws {
        let file=try touch(String(repeating:"字",count:70)+".txt")
        let plan=try FinderCompressionPlan(request:FinderCompressionRequest(files:[file],action:.zip))
        XCTAssertEqual(plan.name,"Archive");XCTAssertEqual(plan.files.count,1)
    }
    func testQuickPresetsFitOneGiBBudgetAndAlwaysVerify()throws {
        for action in FinderCompressionAction.allCases {
            guard let format=action.format else {continue}
            for threads in [-1,1,4,256] {
                let options=FinderCompressionPlan.quickOptions(format:format,threads:threads)
                try options.validate(hasPassword:false)
                XCTAssertTrue((1...4).contains(options.threads));XCTAssertTrue(options.verifyAfterCreation)
                XCTAssertLessThanOrEqual(options.estimatedMemoryBytes,1_073_741_824)
                XCTAssertNil(options.volumeBytes);XCTAssertEqual(options.format,format)
            }
        }
        XCTAssertNil(FinderCompressionAction.custom.format)
    }
    #if os(macOS)
    func testModernPasteboardKeepsEverySelectedFile()async throws {
        let first=try touch("中文 a.txt"),second=try touch("日本語 b.txt")
        try await MainActor.run {
            let board=NSPasteboard.withUniqueName();defer {board.releaseGlobally()}
            XCTAssertTrue(board.writeObjects([first as NSURL,second as NSURL]))
            XCTAssertEqual(try FinderServicesProvider.files(from:board),[first,second])
        }
    }
    func testLegacyFinderPasteboardAndRelativePathRejection()async throws {
        let first=try touch("a.txt"),second=try touch("b.txt")
        try await MainActor.run {
            let board=NSPasteboard.withUniqueName();defer {board.releaseGlobally()}
            let legacy=NSPasteboard.PasteboardType("NSFilenamesPboardType")
            board.setPropertyList([first.path,second.path],forType:legacy)
            XCTAssertEqual(try FinderServicesProvider.files(from:board),[first,second])
            board.setPropertyList(["relative/file"],forType:legacy)
            XCTAssertThrowsError(try FinderServicesProvider.files(from:board))
        }
    }
    func testColdStartRequestSurvivesPasteboardReuseAndIsDeliveredOnce()async throws {
        let file=try touch("startup.txt")
        await MainActor.run {
            let board=NSPasteboard.withUniqueName();defer {board.releaseGlobally()}
            board.writeObjects([file as NSURL])
            let provider=FinderServicesProvider();var error:NSString?
            provider.compressFiles(board,userData:"rar",error:&error)
            XCTAssertNil(error);board.clearContents()
            var received=[FinderCompressionRequest]()
            provider.handler={received.append($0)}
            XCTAssertEqual(received.count,1);XCTAssertEqual(received.first?.files,[file])
            XCTAssertEqual(received.first?.action,.rar)
            provider.handler=nil;provider.handler={received.append($0)}
            XCTAssertEqual(received.count,1)
        }
    }
    func testInvalidServiceActionAndEmptySelectionReturnErrorWithoutPaths()async throws {
        let file=try touch("private-input.txt")
        await MainActor.run {
            let board=NSPasteboard.withUniqueName();defer {board.releaseGlobally()}
            let provider=FinderServicesProvider();var received=0
            provider.handler={_ in received+=1}
            var error:NSString?
            provider.compressFiles(board,userData:"zip",error:&error);XCTAssertNotNil(error)
            board.writeObjects([file as NSURL]);error=nil
            provider.compressFiles(board,userData:"unsupported",error:&error)
            XCTAssertNotNil(error);XCTAssertFalse((error as String? ?? "").contains(file.path));XCTAssertEqual(received,0)
        }
    }
    func testPendingServiceQueueIsBounded()async throws {
        let file=try touch("data.txt")
        await MainActor.run {
            let board=NSPasteboard.withUniqueName();defer {board.releaseGlobally()}
            board.writeObjects([file as NSURL])
            let provider=FinderServicesProvider()
            for _ in 0..<32 {
                var error:NSString?;provider.compressFiles(board,userData:"zip",error:&error);XCTAssertNil(error)
            }
            var error:NSString?;provider.compressFiles(board,userData:"zip",error:&error);XCTAssertNotNil(error)
            var count=0;provider.handler={_ in count+=1};XCTAssertEqual(count,32)
        }
    }
    #endif
}
