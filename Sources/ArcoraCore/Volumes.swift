import Foundation

public struct VolumeSet: Sendable {
    public let first:URL
    public let parts:[URL]
    public var isMultipart:Bool { parts.count>1 }
}
public enum VolumeResolver {
    public static func resolve(_ url:URL) throws -> VolumeSet {
        let directory=url.deletingLastPathComponent()
        let filename=url.lastPathComponent
        let lower=filename.lowercased()
        let siblings=try FileManager.default.contentsOfDirectory(atPath:directory.path).map{directory.appendingPathComponent($0)}
        func match(_ pattern:String,_ text:String)->[String]? {
            guard let regex=try? NSRegularExpression(pattern:pattern,options:[.caseInsensitive]),
                  let result=regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else { return nil }
            return (0..<result.numberOfRanges).map { Range(result.range(at:$0),in:text).map{String(text[$0])} ?? "" }
        }
        func sequence(_ prefix:String,_ pattern:String,_ start:Int)->VolumeSet? {
            var found=[(Int,URL)]()
            for file in siblings {
                if let groups=match(pattern,file.lastPathComponent), let index=Int(groups[1]) { found.append((index,file)) }
            }
            found.sort{$0.0<$1.0}
            guard !found.isEmpty else { return nil }
            return VolumeSet(first:found.first(where:{$0.0==start})?.1 ?? directory.appendingPathComponent(prefix),parts:found.map{$0.1})
        }
        func validate(_ set:VolumeSet,_ pattern:String,_ start:Int) throws -> VolumeSet {
            guard FileManager.default.fileExists(atPath:set.first.path) else { throw ArchiveError.missingVolume(set.first.lastPathComponent) }
            for (offset,part) in set.parts.enumerated() {
                guard let m=match(pattern,part.lastPathComponent),Int(m[1])==offset+start else {
                    throw ArchiveError.missingVolume("Missing volume \(offset+start) near \(filename)")
                }
            }
            return set
        }
        if let m=match("^(.*\\.part)([0-9]+)(\\.rar)$",filename) {
            let prefix=NSRegularExpression.escapedPattern(for:m[1])
            let suffix=NSRegularExpression.escapedPattern(for:m[3])
            let pattern="^"+prefix+"([0-9]+)"+suffix+"$"
            let firstName=m[1]+String(repeating:"0",count:max(0,m[2].count-1))+"1"+m[3]
            if let set=sequence(firstName,pattern,1) { return try validate(set,pattern,1) }
        }
        if let m=match("^(.*)\\.([0-9]{3,})$",filename) {
            let pattern="^"+NSRegularExpression.escapedPattern(for:m[1])+"\\.([0-9]{3,})$"
            if let set=sequence(m[1]+".001",pattern,1) { return try validate(set,pattern,1) }
        }
        // Classic RAR continues past .r99 to .s00, ... .z99.
        let zipPrimaryPresent=match("^(.*)\\.z[0-9]{2,}$",filename).map { groups in
            siblings.contains{$0.lastPathComponent.lowercased()==groups[1].lowercased()+".zip"}
        } ?? false
        if (lower.hasSuffix(".rar") || match("^(.*)\\.[r-z][0-9]{2}$",filename) != nil) && !zipPrimaryPresent {
            let base=url.deletingPathExtension().lastPathComponent
            let primary=siblings.first{$0.lastPathComponent.lowercased()==base.lowercased()+".rar"}
            let pattern="^"+NSRegularExpression.escapedPattern(for:base)+"\\.([r-z])([0-9]{2})$"
            let rest=siblings.compactMap { file -> (Int,URL)? in
                guard let m=match(pattern,file.lastPathComponent),let letter=m[1].lowercased().utf8.first,let number=Int(m[2]) else {return nil}
                return ((Int(letter)-Int(Character("r").asciiValue!))*100+number,file)
            }.sorted{$0.0<$1.0}
            if !rest.isEmpty {
                guard let primary else { throw ArchiveError.missingVolume(base+".rar") }
                for (index,part) in rest.enumerated() where part.0 != index {
                    throw ArchiveError.missingVolume("Missing classic RAR volume \(index+2) near \(filename)")
                }
                return VolumeSet(first:primary,parts:[primary]+rest.map{$0.1})
            }
        }
        // PKZIP split: the final .zip contains the central directory.
        if lower.hasSuffix(".zip") || match("^(.*)\\.z[0-9]{2,}$",filename) != nil {
            let base=url.deletingPathExtension().lastPathComponent
            let pattern="^"+NSRegularExpression.escapedPattern(for:base)+"\\.z([0-9]{2,})$"
            if let rest=sequence(base+".z01",pattern,1) {
                guard let primary=siblings.first(where:{$0.lastPathComponent.lowercased()==base.lowercased()+".zip"}) else { throw ArchiveError.missingVolume(base+".zip") }
                let checked=try validate(rest,pattern,1)
                return VolumeSet(first:primary,parts:checked.parts+[primary])
            }
        }
        guard FileManager.default.fileExists(atPath:url.path) else { throw ArchiveError.io(url.path) }
        return VolumeSet(first:url,parts:[url])
    }
    public static func parseSize(_ text:String) throws -> UInt64? {
        let value=text.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        if value.isEmpty || value=="0" { return nil }
        let regex=try NSRegularExpression(pattern:"^([0-9]+)(?:\\s*)(B|K|KB|KIB|M|MB|MIB|G|GB|GIB)?$")
        guard let m=regex.firstMatch(in:value,range:NSRange(value.startIndex...,in:value)),
              let range=Range(m.range(at:1),in:value),let number=UInt64(value[range]) else { throw ArchiveError.invalid("Use a size such as 100 MiB or 2 GiB.") }
        let suffix=Range(m.range(at:2),in:value).map{String(value[$0])} ?? "B"
        let multiplier:UInt64=suffix.hasPrefix("K") ? 1024 : suffix.hasPrefix("M") ? 1024*1024 : suffix.hasPrefix("G") ? 1024*1024*1024 : 1
        let result=number.multipliedReportingOverflow(by:multiplier)
        guard !result.overflow,result.partialValue>=65536,result.partialValue<=UInt64(Int64.max) else { throw ArchiveError.invalid("Invalid volume size (minimum 64 KiB).") }
        return result.partialValue
    }
}
