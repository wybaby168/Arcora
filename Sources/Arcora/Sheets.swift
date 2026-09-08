#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcoraCore

@MainActor
struct CreateSheet:View {
    @ObservedObject var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var sources:[URL]
    @State private var parent:URL
    @State private var name="Archive"
    @State private var options=CompressionOptions()
    @State private var volume=""
    @State private var password=""
    @State private var confirmation=""
    @State private var advanced=false
    @State private var validation=""
    init(model:AppModel,inputs:[URL]) {
        self.model=model
        _sources=State(initialValue:inputs)
        _parent=State(initialValue:inputs.first?.deletingLastPathComponent() ?? FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask)[0])
        _name=State(initialValue:inputs.count==1 ? (inputs[0].deletingPathExtension().lastPathComponent.isEmpty ? "Archive" : inputs[0].deletingPathExtension().lastPathComponent) : "Archive")
        var defaults=CompressionOptions(); defaults.threads=min(4,max(1,model.preferences.totalThreads));_options=State(initialValue:defaults)
    }
    var body:some View {
        VStack(spacing:0) {
            SheetHeading(icon:"archivebox",title:model.t("compression.title"),subtitle:model.t("compression.subtitle"))
            ScrollView {
                VStack(alignment:.leading,spacing:19) {
                    sourcePanel
                    GroupBox {
                        VStack(spacing:14) {
                            LabeledContent(model.t("field.name")) {TextField(model.t("field.name"),text:$name).textFieldStyle(.roundedBorder).frame(width:385)}
                            LabeledContent(model.t("field.destination")) {destinationPicker}
                            LabeledContent(model.t("field.format")) {
                                Picker("",selection:$options.format) {
                                    ForEach(ArchiveFormat.allCases) { format in
                                        Text(format.title).tag(format)
                                    }
                                }.labelsHidden().frame(width:195)
                                Spacer().frame(width:184)
                            }
                        }.padding(9)
                    }
                    if options.format == .rar && model.engines.rar==nil {
                        Label(model.t("rar.notConfigured"),systemImage:"info.circle").font(.system(size:11)).foregroundStyle(.orange)
                    } else if options.format == .rar && !model.canCreateRAR {
                        Label(model.t("rar.importToCreate"),systemImage:"key.fill").font(.system(size:11)).foregroundStyle(.orange)
                    } else if options.format == .rar {
                        Label(model.t("rar.capabilities"),systemImage:"checkmark.circle").font(.system(size:11)).foregroundStyle(.secondary)
                    }
                    if options.format.singleStream {Text(model.t("compression.singleStream")).font(.system(size:11)).foregroundStyle(.secondary)}
                    GroupBox {
                        VStack(spacing:14) {
                            LabeledContent(model.t("field.level")) {
                                Picker("",selection:$options.level) {
                                    ForEach(options.format.levels,id:\.self) {level in Text(model.t("level.\(level)")).tag(level)}
                                }.labelsHidden().frame(width:385)
                            }
                            LabeledContent(model.t("field.threads")) {
                                Stepper(value:$options.threads,in:1...max(1,model.preferences.totalThreads)) {Text("\(options.threads)").monospacedDigit().frame(width:30,alignment:.trailing)}.frame(width:385,alignment:.leading)
                            }
                            DisclosureGroup(model.t("compression.advanced"),isExpanded:$advanced) {
                                VStack(alignment:.leading,spacing:13) {
                                    LabeledContent(model.t("field.dictionary")) {
                                        if options.format.supportsDictionary {
                                            Picker("",selection:$options.dictionaryMiB) {
                                                ForEach([1,2,4,8,16,32,64,128,256,512,1024],id:\.self) {size in Text("\(size) MiB").tag(size)}
                                            }.labelsHidden().frame(width:200)
                                        } else {Text(options.format == .zip ? "32 KiB · Deflate" : model.t("field.automatic")).foregroundStyle(.secondary)}
                                    }
                                    if options.format.supportsSolid {Toggle(model.t("field.solid"),isOn:$options.solid)}
                                    if options.format.supportsVolumes {
                                        LabeledContent(model.t("field.volumes")) {
                                            TextField(model.t("volume.placeholder"),text:$volume).textFieldStyle(.roundedBorder).frame(width:200)
                                        }
                                        HStack(spacing:6) {
                                            ForEach(["100 MiB","500 MiB","2 GiB"],id:\.self) {value in Button(value){volume=value}.font(.system(size:10))}
                                            Button(model.t("volume.none")){volume=""}.font(.system(size:10))
                                        }
                                        Text(model.t("volume.note")).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                                    }
                                    Toggle(model.t("field.verify"),isOn:$options.verifyAfterCreation)
                                }.padding(.top,12)
                            }.font(.system(size:12))
                        }.padding(9)
                    }
                    if options.format.supportsPassword {encryptionPanel}
                    HStack(spacing:7) {
                        Image(systemName:"memorychip")
                        Text(model.t("compression.estimatedMemory")+" "+ByteCountFormatter.string(fromByteCount:Int64(clamping:options.estimatedMemoryBytes),countStyle:.memory))
                        Spacer()
                        Text(model.t("compression.budget")+" \(model.preferences.memoryGiB) GiB")
                    }.font(.system(size:10)).foregroundStyle(options.estimatedMemoryBytes>model.limits.maxMemoryBytes ? Color.orange : .secondary)
                    if !validation.isEmpty {Label(validation,systemImage:"exclamationmark.circle").font(.system(size:11)).foregroundStyle(.orange)}
                }.padding(.horizontal,25).padding(.vertical,18)
            }
            Divider()
            HStack {
                Label(model.t("compression.keepOriginals"),systemImage:"checkmark.shield").font(.system(size:10)).foregroundStyle(.secondary)
                Spacer()
                Button(model.t("action.cancel")){password="";confirmation="";dismiss()}.keyboardShortcut(.cancelAction)
                Button(model.t("action.compress")){submit()}.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(sources.isEmpty || options.estimatedMemoryBytes>model.limits.maxMemoryBytes || (options.format == .rar && !model.canCreateRAR) || (options.format != .rar && model.engines.sevenZip==nil))
            }.padding(18)
        }.frame(width:710,height:740)
        .onChange(of:options.format) { _,format in
            if !format.levels.contains(options.level) { options.level = format == .tar ? 0 : 5 }
            if !format.supportsPassword {password="";confirmation=""}
            if !format.supportsVolumes {volume=""}
        }
    }
    private var sourcePanel:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text(model.t("compression.sources")).font(.system(size:12,weight:.semibold))
                Text("\(sources.count)").font(.system(size:10,weight:.medium)).foregroundStyle(.secondary)
                Spacer()
                Button {addSources()} label:{Label(model.t("action.add"),systemImage:"plus")}.font(.system(size:11))
            }
            if sources.isEmpty {
                VStack(spacing:7) {
                    Image(systemName:"doc.badge.plus").font(.system(size:22,weight:.light))
                    Text(model.t("compression.dropSources")).font(.system(size:11))
                }.foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:65)
                    .background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:9))
                    .onDrop(of:[UTType.fileURL.identifier],isTargeted:nil) {providers in FileDrop.read(providers){add($0)};return true}
            } else {
                ScrollView {
                    LazyVStack(spacing:8) {
                        ForEach(sources,id:\.path) {url in
                            HStack(spacing:9) {
                                Image(nsImage:NSWorkspace.shared.icon(forFile:url.path)).resizable().frame(width:19,height:19)
                                Text(url.lastPathComponent).font(.system(size:11)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button {sources.removeAll{$0==url}} label:{Image(systemName:"minus.circle").foregroundStyle(.secondary)}.buttonStyle(.plain).help(model.t("action.remove"))
                            }
                        }
                    }.padding(9)
                }.frame(height:min(130,CGFloat(sources.count*30+8))).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:9))
                    .onDrop(of:[UTType.fileURL.identifier],isTargeted:nil) {providers in FileDrop.read(providers){add($0)};return true}
            }
        }
    }
    private var destinationPicker:some View {
        HStack {
            Text(parent.path).font(.system(size:11)).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            Spacer(minLength:5)
            Button(model.t("action.choose")) {if let url=FolderPicker.choose(message:model.t("field.destination"),initial:parent){parent=url}}
        }.frame(width:385)
    }
    private var encryptionPanel:some View {
        GroupBox {
            VStack(alignment:.leading,spacing:13) {
                Label(model.t("encryption.title"),systemImage:"lock").font(.system(size:12,weight:.medium))
                LabeledContent(model.t("field.password")){SecureField(model.t("encryption.optional"),text:$password).textFieldStyle(.roundedBorder).frame(width:385)}
                if !password.isEmpty {
                    LabeledContent(model.t("field.confirmPassword")){SecureField("",text:$confirmation).textFieldStyle(.roundedBorder).frame(width:385)}
                    if options.format == .sevenZip || options.format == .rar {Toggle(model.t("field.encryptHeaders"),isOn:$options.encryptHeaders)}
                    if options.format == .zip {
                        LabeledContent(model.t("field.encryption")) {
                            Picker("",selection:$options.zipEncryption) {Text("AES-256").tag(ZIPEncryption.aes256);Text("ZipCrypto · "+model.t("encryption.legacy")).tag(ZIPEncryption.zipCrypto)}.labelsHidden().frame(width:250)
                        }
                        Text(model.t(options.zipEncryption == .zipCrypto ? "encryption.weakWarning" : "encryption.aesNote")).font(.system(size:10)).foregroundStyle(.secondary)
                        Text(model.t("encryption.zipPasswordNote")).font(.system(size:10)).foregroundStyle(.secondary)
                    }
                }
                Text(model.t("encryption.memoryOnly")).font(.system(size:10)).foregroundStyle(.secondary)
            }.padding(9)
        }
    }
    private func addSources() {
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=true;panel.allowsMultipleSelection=true
        if panel.runModal() == .OK {add(panel.urls)}
    }
    private func add(_ urls:[URL]) {for url in urls where !sources.contains(url) {sources.append(url)}}
    private func submit() {
        validation=""
        guard password==confirmation else{validation=model.t("encryption.mismatch");return}
        if options.format == .zip,!password.isEmpty,
           (!password.utf8.allSatisfy{$0>=32 && $0<127} || (options.zipEncryption == .aes256 && password.utf8.count>99)) {
            validation=model.t("encryption.zipPasswordNote");return
        }
        do {
            try PathSafety.safeFilename(name)
            options.volumeBytes=try VolumeResolver.parseSize(volume)
            model.submitCreate(inputs:sources,parent:parent,name:name,options:options,password:password)
            if !model.showCreate {password="";confirmation=""}
        } catch {validation=model.t((error as? ArchiveError)?.localizationKey ?? "error.invalid")+" "+error.localizedDescription}
    }
}
@MainActor
struct ExtractionSheet:View {
    @ObservedObject var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var parent:URL
    @State private var name:String
    @State private var validation=""
    init(model:AppModel) {
        self.model=model
        let source=model.manifest?.source ?? FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask)[0]
        _parent=State(initialValue:source.deletingLastPathComponent())
        _name=State(initialValue:ArchiveService.defaultFolderName(source))
    }
    var body:some View {
        VStack(spacing:0) {
            SheetHeading(icon:"arrow.down.doc",title:model.t("extraction.title"),subtitle:model.manifest?.source.lastPathComponent ?? "")
            VStack(alignment:.leading,spacing:19) {
                LabeledContent(model.t("field.destination")) {
                    Text(parent.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button(model.t("action.choose")){if let url=FolderPicker.choose(message:model.t("field.destination"),initial:parent){parent=url}}
                }
                LabeledContent(model.t("extraction.folder")) {TextField("",text:$name).textFieldStyle(.roundedBorder).frame(width:325)}
                LabeledContent(model.t("extraction.scope")) {Text(model.extractionSelection==nil ? model.t("extraction.all") : "\(model.extractionSelection?.count ?? 0) "+model.t("browser.selected")).foregroundStyle(.secondary)}
                Text(model.t("extraction.safeDestination")).font(.system(size:11)).foregroundStyle(.secondary).lineSpacing(4)
                Label(model.t("extraction.volumesNote"),systemImage:"square.stack").font(.system(size:11)).foregroundStyle(.secondary)
                if !validation.isEmpty {Text(validation).font(.system(size:11)).foregroundStyle(.orange)}
            }.padding(26)
            Divider()
            HStack {
                Spacer()
                Button(model.t("action.cancel")){dismiss()}.keyboardShortcut(.cancelAction)
                Button(model.t("action.extract")) {
                    do{try PathSafety.safeFilename(name);model.submitExtract(parent:parent,name:name)}catch{validation=model.t("error.invalid")}
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(18)
        }.frame(width:600)
    }
}
@MainActor
struct PasswordSheet:View {
    @ObservedObject var model:AppModel
    @State private var password=""
    @FocusState private var focused:Bool
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(spacing:13) {
                Image(systemName:"lock.circle").font(.system(size:36,weight:.light)).foregroundStyle(Color.accentColor)
                VStack(alignment:.leading,spacing:5) {Text(model.t("password.title")).font(.headline);Text(model.t("password.subtitle")).font(.system(size:11)).foregroundStyle(.secondary)}
            }
            SecureField(model.t("field.password"),text:$password).textFieldStyle(.roundedBorder).focused($focused).onSubmit{submitted()}
            Text(model.t("encryption.memoryOnly")).font(.system(size:10)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(model.t("action.cancel")){password="";model.dismissPassword()}.keyboardShortcut(.cancelAction)
                Button(model.t("action.unlock")){submitted()}.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(password.isEmpty)
            }
        }.padding(26).frame(width:460).onAppear{focused=true}
    }
    private func submitted(){let value=password;password="";model.providePassword(value)}
}
@MainActor
struct SheetHeading:View {
    let icon:String,title:String,subtitle:String
    var body:some View {
        HStack(spacing:13) {
            Image(systemName:icon).font(.system(size:25,weight:.light)).foregroundStyle(Color.accentColor)
                .frame(width:46,height:46).background(Color.accentColor.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
            VStack(alignment:.leading,spacing:5) {
                Text(title).font(.system(size:20,weight:.semibold))
                Text(subtitle).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
        }.padding(24)
        Divider()
    }
}
enum FolderPicker {
    @MainActor static func choose(message:String,initial:URL?=nil)->URL? {
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=true
        panel.allowsMultipleSelection=false;panel.message=message;panel.directoryURL=initial
        return panel.runModal() == .OK ? panel.url : nil
    }
}
#endif
