#!/usr/bin/swift
// Verify the delivered ICNS, not just the source file extension.
import AppKit
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("Icon validation failed: " + message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count==2 else {fail("Usage: verify-icon.swift ICON.icns")}
let icon=URL(fileURLWithPath:CommandLine.arguments[1])
let directory=FileManager.default.temporaryDirectory.appendingPathComponent("Arcora-icon-check-"+UUID().uuidString+".iconset")
defer {try? FileManager.default.removeItem(at:directory)}
let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/iconutil")
process.arguments=["-c","iconset",icon.path,"-o",directory.path]
try process.run();process.waitUntilExit()
guard process.terminationStatus==0 else {fail("The ICNS could not be decoded")}
var count=0
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=size*scale
        let name="icon_\(size)x\(size)"+(scale==2 ? "@2x" : "")+".png"
        let url=directory.appendingPathComponent(name)
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),
              let image=CGImageSourceCreateImageAtIndex(source,0,nil),
              image.width==pixels,image.height==pixels else {fail("Missing or incorrectly sized icon: "+name)}
        var bytes=[UInt8](repeating:0,count:pixels*pixels*4)
        bytes.withUnsafeMutableBytes { storage in
            guard let context=CGContext(data:storage.baseAddress,width:pixels,height:pixels,bitsPerComponent:8,
                bytesPerRow:pixels*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,
                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {fail("Cannot inspect icon pixels")}
            context.draw(image,in:CGRect(x:0,y:0,width:pixels,height:pixels))
        }
        var visible=0
        let padding=max(1,pixels/32)
        for y in 0..<pixels {
            for x in 0..<pixels {
                let alpha=bytes[(y*pixels+x)*4+3]
                if alpha>16 {visible+=1}
                if x<padding || y<padding || x>=pixels-padding || y>=pixels-padding {
                    guard alpha<=3 else {fail("Stray pixels in the transparent outer padding: "+name)}
                }
            }
        }
        let coverage=Double(visible)/Double(pixels*pixels)
        guard coverage>0.45,coverage<0.90 else {fail("Empty artwork or flattened background: "+name)}
        count+=1
    }
}
print("PASS: \(count) native icon representations, 16–1024 px; nonempty artwork and clean transparent padding")
