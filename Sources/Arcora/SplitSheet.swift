#if os(macOS)
import SwiftUI
import ArcoraCore

@MainActor
struct SplitSheet:View {
    @ObservedObject var model:AppModel
    let source:URL
    @Environment(\.dismiss) private var dismiss
    @State private var parent:URL
    @State private var name:String
    @State private var size="2 GiB"
    init(model:AppModel,source:URL) {
        self.model=model;self.source=source
        _parent=State(initialValue:source.deletingLastPathComponent())
        _name=State(initialValue:source.lastPathComponent)
    }
    var body:some View {
        VStack(spacing:0) {
            SheetHeading(icon:"square.split.2x1",title:model.t("action.split"),subtitle:source.lastPathComponent)
            VStack(alignment:.leading,spacing:18) {
                LabeledContent(model.t("field.name")) {
                    TextField(model.t("field.name"),text:$name).textFieldStyle(.roundedBorder).frame(width:350).accessibilityIdentifier("splitName")
                }.accessibilityElement(children:.contain)
                LabeledContent(model.t("field.destination")) {
                    HStack {
                        Text(parent.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Spacer()
                        Button(model.t("action.choose")) {
                            if let folder=FolderPicker.choose(message:model.t("field.destination"),initial:parent) {parent=folder}
                        }
                    }.frame(width:350)
                }.accessibilityElement(children:.contain)
                LabeledContent(model.t("field.volumes")) {
                    HStack {
                        TextField(model.t("volume.placeholder"),text:$size).textFieldStyle(.roundedBorder)
                            .accessibilityLabel(model.t("field.volumes")).accessibilityIdentifier("splitPartSize")
                        Menu {
                            ForEach(["100 MiB","500 MiB","2 GiB"],id:\.self) {value in Button(value){size=value}}
                        } label:{Image(systemName:"chevron.down")}.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel(model.t("field.volumes"))
                    }.frame(width:350)
                }.accessibilityElement(children:.contain)
                Text(model.t("split.description")).font(.system(size:11)).foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            HStack {
                Spacer()
                Button(model.t("action.cancel")) {dismiss()}.keyboardShortcut(.cancelAction)
                Button(model.t("split.start")) {
                    model.submitSplit(source:source,parent:parent,name:name,partSize:size)
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(name.isEmpty || size.isEmpty)
            }.padding(18)
        }.frame(width:580)
    }
}
#endif
