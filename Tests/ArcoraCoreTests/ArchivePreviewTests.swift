import Foundation
import XCTest
@testable import ArcoraCore

final class ArchivePreviewTests:ArcoraTestCase {
    private func services() throws -> [ArchiveService] {
        let native=try nativeService()
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let engine=ProcessInfo.processInfo.environment["ARCORA_7ZZ"].map{URL(fileURLWithPath:$0)} ?? root.appendingPathComponent("Vendor/7zip/7zz")
        guard FileManager.default.isExecutableFile(atPath:engine.path) else {
            if ProcessInfo.processInfo.environment["ARCORA_REQUIRE_7ZZ"]=="1" { throw ArchiveError.missingEngine("The official 7zz is required.") }
            return [native]
        }
        return [native,ArchiveService(engines:EngineLocations(sevenZip:engine,worker:try worker()))]
    }

    /// Benign project data with a relative documentation link, a hard link and a FIFO.
    /// No archived program is run, and no member points outside the project.
    private func projectArchives() throws -> [URL] {
        let python=URL(fileURLWithPath:"/usr/bin/python3")
        guard FileManager.default.isExecutableFile(atPath:python.path) else { throw XCTSkip("Python 3 is required to generate test archives.") }
        let script="""
        import io, pathlib, stat, sys, tarfile, zipfile
        root = pathlib.Path(sys.argv[1])
        files = {
            'project/docs/readme.txt': b'Arcora preview.\\n',
            'project/docs/nested/value.txt': b'Nested document.\\n',
            'project/literal*.txt': b'Literal asterisk.\\n',
            'project/literal?.txt': b'Literal question mark.\\n',
            'project/large.txt': b'A' * 2048,
        }
        with zipfile.ZipFile(root / 'project.zip', 'w') as archive:
            link = zipfile.ZipInfo('project/readme-link')
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(link, b'docs/readme.txt')
            for name, data in files.items():
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                entry.external_attr = (stat.S_IFREG | 0o755) << 16
                archive.writestr(entry, data)
        with tarfile.open(root / 'project.tar', 'w') as archive:
            for name, kind, target in [
                ('project/readme-link', tarfile.SYMTYPE, 'docs/readme.txt'),
                ('project/readme-hardlink', tarfile.LNKTYPE, 'project/docs/readme.txt'),
                ('project/pipe', tarfile.FIFOTYPE, ''),
            ]:
                entry = tarfile.TarInfo(name)
                entry.type = kind
                entry.linkname = target
                archive.addfile(entry)
            for name, data in files.items():
                entry = tarfile.TarInfo(name)
                entry.size = len(data)
                entry.mode = 0o755
                archive.addfile(entry, io.BytesIO(data))
        """
        let result=try ProcessRunner().run(EngineCommand(python,["-c",script,temp.path]))
        try ProcessRunner.requireSuccess(result,passwordSupplied:false)
        return ["project.zip","project.tar"].map{temp.appendingPathComponent($0)}
    }

    func testLinkedProjectCanBeBrowsedAndRegularFilePreviewed() throws {
        for service in try services() {
            for archive in try projectArchives() {
                let original=try Data(contentsOf:archive)
                let manifest=try service.inspect(archive)
                XCTAssertEqual(manifest.entries.filter{$0.isMetadataOnly}.count,archive.pathExtension=="tar" ? 3 : 1)
                let file=try service.preview(archive,entry:"project/docs/readme.txt",in:temp)
                XCTAssertEqual(try String(contentsOf:file),"Arcora preview.\n")
                let permissions=try FileManager.default.attributesOfItem(atPath:file.path)[.posixPermissions] as? NSNumber
                XCTAssertEqual(try XCTUnwrap(permissions).intValue & 0o111,0)
                let root=file.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("project/readme-link").path))
                XCTAssertEqual(try Data(contentsOf:archive),original)
            }
        }
    }

    func testSelectedOrdinaryDirectoryAndLiteralFilenames() throws {
        for service in try services() {
            for archive in try projectArchives() {
                for selection:Set<String> in [["project/docs"],["project/literal*.txt"],["project/literal?.txt"]] {
                    let output=try service.extract(archive,to:temp,name:UUID().uuidString,selection:selection).outputs[0]
                    XCTAssertFalse(FileManager.default.fileExists(atPath:output.appendingPathComponent("project/readme-link").path))
                    XCTAssertFalse(FileManager.default.fileExists(atPath:output.appendingPathComponent("project/large.txt").path))
                    if selection.contains("project/docs") {
                        XCTAssertEqual(try String(contentsOf:output.appendingPathComponent("project/docs/nested/value.txt")),"Nested document.\n")
                    } else {
                        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:output.appendingPathComponent("project").path).count,1)
                        XCTAssertTrue(FileManager.default.fileExists(atPath:output.appendingPathComponent(selection.first!).path))
                    }
                }
            }
        }
    }

    func testLinksAndTheirContainingDirectoriesFailBeforeWriting() throws {
        for service in try services() {
            for archive in try projectArchives() {
                var selections:[Set<String>?]=[nil,["project"],["project/readme-link"],["."]]
                if archive.pathExtension=="tar" { selections += [["project/readme-hardlink"],["project/pipe"]] }
                for selection in selections {
                    let name=UUID().uuidString
                    XCTAssertThrowsError(try service.extract(archive,to:temp,name:name,selection:selection)) {
                        guard case .metadataOnly = $0 as? ArchiveError else { return XCTFail("Unexpected error \($0)") }
                    }
                    XCTAssertThrowsError(try service.preview(archive,entry:"project/readme-link",in:temp))
                    XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent(name).path))
                }
                XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:temp.path).contains{$0.hasPrefix(".arcora-")})
            }
        }
    }

    func testCatalogAndSmallPreviewUseSeparateExpansionBudgets() throws {
        for base in try services() {
            var limits=base.limits
            limits.maxExpandedBytes=32
            let service=ArchiveService(engines:base.engines,limits:limits)
            let source=fixture("normal.zip")
            XCTAssertEqual(try service.inspect(source).entries.count,4)
            let file=try service.preview(source,entry:"hello.txt",in:temp)
            XCTAssertEqual(try String(contentsOf:file),"Hello from Arcora.\n")
            XCTAssertThrowsError(try service.preview(source,entry:"nested/deep/value.bin",in:temp))
            XCTAssertThrowsError(try service.extract(source,to:temp,name:"over-budget"))
            XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent("over-budget").path))
        }
    }

    func testMissingSelectionCannotSilentlySucceed() throws {
        let manifest=ArchiveManifest(source:temp,backend:.libarchive,entries:[ArchiveEntry(path:"project/docs/readme.txt")],format:"ZIP")
        XCTAssertEqual(try manifest.selectedEntries(["project","project/docs"]).count,1)
        XCTAssertEqual(try manifest.selectedEntries(["."]).count,1)
        XCTAssertThrowsError(try manifest.selectedEntries(["project/docs/readme.txt","missing.txt"]))
        XCTAssertThrowsError(try manifest.selectedEntries([]))
    }

    func testZIPUnixMetadataTypesAreRecognized() throws {
        for mode in ["l---------","lr-xr-xr-x","prw-r--r--","brw-------","crw-------","srwxr-xr-x"] {
            let entries=try SLTParser.parse("Path = project/item\nSize = 0\nAttributes =  \(mode)\n\n")
            XCTAssertTrue(try XCTUnwrap(entries.first).isMetadataOnly,mode)
        }
    }
}
