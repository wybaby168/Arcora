import AppKit
import SwiftUI

// Compile alongside the production BrandIcon.swift, without starting the app
// or changing user preferences. Only the resource-bundle provider is replaced.
@MainActor
enum AppResources {
    static let bundle:Bundle = {
        if CommandLine.arguments.contains("--fallback") { return Bundle.main }
        let resources=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
            .appendingPathComponent("Contents/Resources",isDirectory:true)
        for name in ["Arcora_Arcora.bundle","Arcora_Arcora.resources"] {
            if let bundle=Bundle(url:resources.appendingPathComponent(name)) {return bundle}
        }
        BrandIconValidation.fail("Packaged SwiftPM resource bundle is missing")
    }()
}

@main
@MainActor
struct BrandIconValidation {
    struct Raster {
        let image:CGImage
        let pixels:[UInt8]
        var visiblePixels:Int {stride(from:3,to:pixels.count,by:4).filter{pixels[$0]>10}.count}
    }

    static func fail(_ message:String)->Never {
        FileHandle.standardError.write(Data("Brand icon check failed: \(message)\n".utf8))
        exit(1)
    }

    static func render<V:View>(_ view:V,scheme:ColorScheme,scale:CGFloat)->Raster {
        let renderer=ImageRenderer(content:view.environment(\.colorScheme,scheme))
        renderer.scale=scale
        guard let image=renderer.cgImage else {fail("SwiftUI did not render an image")}
        var pixels=[UInt8](repeating:0,count:image.width*image.height*4)
        let drew=pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context=CGContext(data:bytes.baseAddress,width:image.width,height:image.height,
                bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,
                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {return false}
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            return true
        }
        guard drew else {fail("Could not read rendered pixels")}
        return Raster(image:image,pixels:pixels)
    }

    static func main() {
        let args=CommandLine.arguments
        guard args.count>=2 else {fail("Usage: verify-brand-icon APP [--snapshots DIRECTORY]")}
        let fallback=args.contains("--fallback")
        let reference:Image
        if fallback {
            guard AppResources.bundle.url(forResource:"ArcoraIcon",withExtension:"png")==nil else {
                fail("Fallback fixture unexpectedly contains the artwork")
            }
            reference=Image(systemName:"shippingbox.fill")
        } else {
            guard let url=AppResources.bundle.url(forResource:"ArcoraIcon",withExtension:"png"),
                  let artwork=NSImage(contentsOf:url),artwork.isValid else {
                fail("Packaged ArcoraIcon.png is missing or cannot be decoded")
            }
            reference=Image(nsImage:artwork)
        }
        var snapshots:URL?
        if let option=args.firstIndex(of:"--snapshots") {
            guard option+1<args.count else {fail("Missing snapshot directory")}
            snapshots=URL(fileURLWithPath:args[option+1],isDirectory:true)
            do {try FileManager.default.createDirectory(at:snapshots!,withIntermediateDirectories:true)}
            catch {fail("Could not create snapshot directory: \(error)")}
        }
        for size:CGFloat in [44,88] {
            for scale:CGFloat in [1,2] {
                for scheme:ColorScheme in [.light,.dark] {
                    let actual=render(BrandIcon(size:size),scheme:scheme,scale:scale)
                    let expected=render(reference.renderingMode(.original).resizable().interpolation(.high)
                        .aspectRatio(contentMode:.fit).frame(width:size,height:size),scheme:scheme,scale:scale)
                    let label="\(Int(size))pt @\(Int(scale))x \(scheme == .light ? "light" : "dark")"
                    guard actual.image.width==Int(size*scale),actual.image.height==Int(size*scale),
                          actual.visiblePixels>Int(size*size*scale*scale*0.1) else {
                        fail("\(label): empty or incorrectly sized artwork (\(actual.visiblePixels) visible pixels)")
                    }
                    guard actual.pixels==expected.pixels else {
                        fail("\(label): rendered view does not match the \(fallback ? "fallback symbol" : "packaged artwork")")
                    }
                    if let snapshots {
                        let name="\(fallback ? "fallback" : "brand")-\(Int(size))-\(Int(scale))x-\(scheme == .light ? "light" : "dark").png"
                        guard let data=NSBitmapImageRep(cgImage:actual.image).representation(using:.png,properties:[:]) else {
                            fail("Could not encode snapshot")
                        }
                        do {try data.write(to:snapshots.appendingPathComponent(name),options:.atomic)}
                        catch {fail("Could not save snapshot: \(error)")}
                    }
                    print("PASS: \(fallback ? "fallback" : "packaged artwork") \(label), \(actual.visiblePixels) visible pixels")
                }
            }
        }
    }
}
