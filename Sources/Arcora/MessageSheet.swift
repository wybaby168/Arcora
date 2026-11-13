#if os(macOS)
import AppKit
import SwiftUI

extension View {
    @MainActor
    func presentingMessages(_ model:AppModel,enabled:Bool=true)->some View {
        sheet(item:Binding(get:{enabled ? model.error : nil},set:{model.error=$0})) {
            MessageSheet(model:model,message:$0)
        }
    }
}

@MainActor
struct ReadOnlyText:NSViewRepresentable {
    let text:String
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView()
        scroll.hasVerticalScroller=true
        scroll.autohidesScrollers=true
        scroll.borderType = .noBorder
        let content=NSTextView()
        content.isEditable=false
        content.isSelectable=true
        content.isRichText=false
        content.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        content.textColor = .textColor
        content.backgroundColor = .textBackgroundColor
        content.textContainerInset=NSSize(width:12,height:12)
        content.isHorizontallyResizable=false
        content.isVerticallyResizable=true
        content.autoresizingMask=[.width]
        content.textContainer?.widthTracksTextView=true
        scroll.documentView=content
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        guard let content=scroll.documentView as? NSTextView,content.string != text else {return}
        content.string=text
    }
}

@MainActor
struct MessageSheet:View {
    @ObservedObject var model:AppModel
    let message:UIError
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text(message.title).font(.system(size:17,weight:.semibold)).textSelection(.enabled)
            ReadOnlyText(text:message.detail)
                .frame(height:260)
                .clipShape(RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(.quaternary,lineWidth:0.5))
            HStack {
                Button(model.t("action.copyDetails")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.title+"\n\n"+message.detail,forType:.string)
                }
                Spacer()
                Button(model.t("action.close")) {model.error=nil}.keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width:620)
    }
}
#endif
