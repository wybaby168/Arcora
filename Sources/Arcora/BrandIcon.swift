#if os(macOS)
import AppKit
import SwiftUI

/// Use the same master as Finder and Dock. This mark is decorative next to the
/// app name; archive action buttons continue to use familiar SF Symbols.
@MainActor
struct BrandIcon:View {
    var size:CGFloat
    // SwiftPM ships this PNG as a loose bundle resource. SwiftUI's named-image
    // lookup can render it as an empty image even when Bundle finds the file.
    // Decode the explicit URL once, then share it between sidebar and About.
    private static let artwork:NSImage? = {
        guard let url=AppResources.bundle.url(forResource:"ArcoraIcon",withExtension:"png"),
              let image=NSImage(contentsOf:url),image.isValid else {return nil}
        return image
    }()
    private var image:Image {
        if let artwork=Self.artwork {return Image(nsImage:artwork)}
        return Image(systemName:"shippingbox.fill")
    }
    var body:some View {
        image
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode:.fit)
            .frame(width:size,height:size)
            .accessibilityHidden(true)
    }
}
#endif
