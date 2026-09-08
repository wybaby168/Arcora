#!/usr/bin/swift
// Render the app's own vector mark at native icon resolutions; no external assets.
import AppKit
import Foundation

guard CommandLine.arguments.count==2 else { fatalError("Usage: make-icon.swift OUTPUT.icns") }
let destination=URL(fileURLWithPath:CommandLine.arguments[1])
let folder=FileManager.default.temporaryDirectory.appendingPathComponent("Arcora-"+UUID().uuidString+".iconset")
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
defer { try? FileManager.default.removeItem(at:folder) }
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=size*scale
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:bitmap) else {fatalError("Icon allocation failed")}
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
        let factor=CGFloat(pixels)/1024
        let transform=NSAffineTransform();transform.scale(by:factor);transform.concat()
        let background=NSBezierPath(roundedRect:NSRect(x:82,y:82,width:860,height:860),xRadius:190,yRadius:190)
        NSGradient(starting:NSColor(calibratedRed:0.38,green:0.46,blue:0.81,alpha:1),ending:NSColor(calibratedRed:0.22,green:0.27,blue:0.59,alpha:1))!.draw(in:background,angle:-70)
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let body=NSBezierPath(roundedRect:NSRect(x:279,y:278,width:466,height:385),xRadius:39,yRadius:39);body.lineWidth=24;body.stroke()
        let lid=NSBezierPath(roundedRect:NSRect(x:247,y:649,width:530,height:95),xRadius:26,yRadius:26);lid.lineWidth=24;lid.stroke()
        let slit=NSBezierPath();slit.move(to:NSPoint(x:450,y:551));slit.line(to:NSPoint(x:574,y:551));slit.lineWidth=25;slit.lineCapStyle = .round;slit.stroke()
        let arrow=NSBezierPath();arrow.move(to:NSPoint(x:512,y:347));arrow.line(to:NSPoint(x:512,y:465));arrow.move(to:NSPoint(x:467,y:420));arrow.line(to:NSPoint(x:512,y:465));arrow.line(to:NSPoint(x:557,y:420));arrow.lineWidth=23;arrow.lineCapStyle = .round;arrow.lineJoinStyle = .round;arrow.stroke()
        NSGraphicsContext.restoreGraphicsState()
        guard let data=bitmap.representation(using:.png,properties:[:]) else {fatalError("PNG encoding failed")}
        let name="icon_\(size)x\(size)"+(scale==2 ? "@2x" : "")+".png"
        try data.write(to:folder.appendingPathComponent(name))
    }
}
let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/iconutil")
process.arguments=["-c","icns",folder.path,"-o",destination.path]
try process.run();process.waitUntilExit()
guard process.terminationStatus==0 else {fatalError("iconutil failed")}
