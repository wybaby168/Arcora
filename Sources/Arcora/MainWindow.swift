#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookUI
import ArcoraCore

@MainActor
struct MainWindow:View {
    @ObservedObject var model:AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var dropTarget=false
    var body:some View {
        NavigationSplitView {
            SidebarView(model:model)
                .navigationSplitViewColumnWidth(min:184,ideal:204,max:240)
        } detail: {
            Group {
                if model.page == .activity { ActivityView(model:model) }
                else if model.isLoading { LoadingView(model:model) }
                else if model.manifest != nil { ArchiveBrowser(model:model) }
                else { WelcomeView(model:model) }
            }
            .background(Color(nsColor:.windowBackgroundColor))
            .overlay {
                if dropTarget {
                    RoundedRectangle(cornerRadius:18).fill(Color.accentColor.opacity(0.07)).overlay {
                        RoundedRectangle(cornerRadius:18).strokeBorder(Color.accentColor,style:StrokeStyle(lineWidth:2,dash:[8]))
                    }.padding(14).allowsHitTesting(false)
                }
            }
            .onDrop(of:[UTType.fileURL.identifier],isTargeted:$dropTarget) { providers in
                FileDrop.read(providers) { model.handleDrop($0) };return true
            }
        }
        .frame(minWidth:940,minHeight:620)
        .tint(Color(red:0.28,green:0.36,blue:0.79))
        .onAppear {
            let action=openWindow
            // A Window is unique: reopening only raises/restores the workspace.
            model.reopenMainWindow={action(id:"main")}
            model.processFinderRequests()
        }
        .onChange(of:model.hasPresentedDialog) { _,presented in
            if !presented {model.processFinderRequests()}
        }
        .toolbar {
            ToolbarItemGroup(placement:.automatic) {
                Button {model.chooseArchive()} label:{Label(model.t("action.open"),systemImage:"folder")}.help(model.t("action.open"))
                Button {model.presentCreate()} label:{Label(model.t("action.new"),systemImage:"plus")}.help(model.t("action.new"))
                if model.manifest != nil && model.page == .workspace {
                    Divider()
                    Button {model.requestTest()} label:{Label(model.t("action.test"),systemImage:"checkmark.shield")}
                    Button {model.presentExtract()} label:{Label(model.t("action.extract"),systemImage:"arrow.down.to.line")}
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented:$model.showCreate) { CreateSheet(model:model,inputs:model.createSources) }
        .sheet(isPresented:$model.showExtraction) { ExtractionSheet(model:model) }
        .sheet(isPresented:$model.showPassword,onDismiss:{model.dismissPassword()}) { PasswordSheet(model:model) }
        .sheet(isPresented:$model.showGuide) { GuideView(model:model) }
        .sheet(isPresented:Binding(get:{model.previewURL != nil},set:{if !$0 {model.dismissPreview()}})) {
            if let url=model.previewURL { PreviewSheet(model:model,url:url) }
        }
        .alert(item:$model.error) { item in
            Alert(title:Text(item.title),message:Text(String(item.detail.prefix(3000))),dismissButton:.default(Text(model.t("action.ok"))))
        }
    }
}
@MainActor
struct SidebarView:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:24) {
            HStack(spacing:10) {
                BrandIcon(size:44)
                VStack(alignment:.leading,spacing:1) {
                    Text("Arcora").font(.system(size:20,weight:.semibold,design:.rounded))
                    Text(model.t("app.descriptor")).font(.system(size:10,weight:.medium)).foregroundStyle(.secondary)
                }
            }.padding(.top,16)
            VStack(spacing:5) {
                navButton(.workspace,"nav.workspace","square.stack.3d.up")
                navButton(.activity,"nav.activity","arrow.triangle.2.circlepath",count:model.activeJobs.count)
            }
            if !model.recents.isEmpty {
                VStack(alignment:.leading,spacing:10) {
                    Text(model.t("nav.recent")).font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary).padding(.horizontal,10)
                    ForEach(Array(model.recents.prefix(5)),id:\.path) { url in
                        Button {model.open(url)} label:{
                            HStack(spacing:9) {
                                Image(systemName:"doc.zipper").foregroundStyle(.secondary)
                                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength:0)
                            }.font(.system(size:11)).padding(.horizontal,10).padding(.vertical,5).contentShape(Rectangle())
                        }.buttonStyle(.plain).help(url.path)
                    }
                }
            }
            Spacer()
            VStack(alignment:.leading,spacing:14) {
                HStack(spacing:6) {
                    Image(systemName:"lock.shield").font(.system(size:12))
                    Text(model.t("privacy.local")).font(.system(size:10,weight:.medium))
                }.foregroundStyle(.secondary)
                Divider()
                HStack {
                    SettingsLink {Label(model.t("nav.settings"),systemImage:"gearshape")}.buttonStyle(.plain).font(.system(size:12))
                    Spacer()
                    Button {model.showGuide=true} label:{Image(systemName:"questionmark.circle")}.buttonStyle(.plain).help(model.t("action.guide"))
                }.foregroundStyle(.secondary)
            }.padding(.bottom,14)
        }.padding(.horizontal,14)
    }
    private func navButton(_ page:SectionPage,_ key:String,_ icon:String,count:Int=0)->some View {
        Button {model.page=page} label:{
            HStack(spacing:10) {
                Image(systemName:icon).frame(width:17)
                Text(model.t(key)).font(.system(size:12,weight:model.page==page ? .semibold : .regular))
                Spacer()
                if count>0 {Text("\(count)").font(.system(size:10,weight:.semibold)).padding(.horizontal,6).padding(.vertical,2).background(.quaternary,in:Capsule())}
            }.padding(.horizontal,10).padding(.vertical,10).contentShape(RoundedRectangle(cornerRadius:8))
                .background(model.page==page ? Color.accentColor.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:8))
                .foregroundStyle(model.page==page ? Color.accentColor : .primary)
        }.buttonStyle(.plain)
    }
}
@MainActor
struct WelcomeView:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(spacing:0) {
            Spacer(minLength:28)
            Image(systemName:"archivebox").font(.system(size:48,weight:.ultraLight)).foregroundStyle(Color.accentColor)
                .frame(width:104,height:104).background(Color.accentColor.opacity(0.065),in:RoundedRectangle(cornerRadius:29))
                .padding(.bottom,26)
            Text(model.t("app.tagline")).font(.system(size:29,weight:.semibold,design:.rounded))
            Text(model.t("welcome.subtitle")).font(.system(size:13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .lineSpacing(5).padding(.top,12)
            HStack(spacing:10) {
                Button {model.chooseArchive()} label:{Label(model.t("action.open"),systemImage:"folder")}.buttonStyle(.borderedProminent)
                Button {model.presentCreate()} label:{Label(model.t("action.new"),systemImage:"plus")}.buttonStyle(.bordered)
            }.controlSize(.large).padding(.top,28)
            Text(model.t("welcome.drag")).font(.system(size:11)).foregroundStyle(.tertiary).padding(.top,16)
            HStack(spacing:9) {
                ForEach(["7Z","ZIP","RAR","TAR","ISO","+"],id:\.self) { format in
                    Text(format).font(.system(size:9,weight:.medium,design:.monospaced)).foregroundStyle(.secondary)
                        .padding(.horizontal,9).padding(.vertical,5).background(.quaternary.opacity(0.45),in:RoundedRectangle(cornerRadius:5))
                }
            }.padding(.top,35)
            Spacer(minLength:40)
            if model.engines.sevenZip==nil {
                HStack(spacing:8) {
                    Image(systemName:"exclamationmark.triangle")
                    Text(model.t("engine.missing")).font(.system(size:11))
                    Button(model.t("action.guide")){model.showGuide=true}
                }.foregroundStyle(.orange).padding(14).frame(maxWidth:.infinity).background(.quaternary.opacity(0.3))
            } else {
                HStack(spacing:18) {
                    Label(model.t("welcome.native"),systemImage:"cpu")
                    Label(model.t("welcome.offline"),systemImage:"wifi.slash")
                    Label(model.t("welcome.noAds"),systemImage:"sparkle")
                }.font(.system(size:10)).foregroundStyle(.tertiary).padding(.bottom,24)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}
@MainActor
struct LoadingView:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(spacing:16) {
            ProgressView().controlSize(.large)
            Text(model.t("phase.reading")).foregroundStyle(.secondary)
            Button(model.t("action.cancel")){model.closeArchive()}.buttonStyle(.bordered)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}
@MainActor
struct ArchiveBrowser:View {
    @ObservedObject var model:AppModel
    @State private var order=[KeyPathComparator(\ArchiveRow.name)]
    var body:some View {
        VStack(spacing:0) {
            header
            Divider()
            HStack(spacing:7) {
                Button {model.currentFolder="";model.search="";model.selection=[]} label:{Image(systemName:"house")}.buttonStyle(.plain)
                ForEach(breadcrumbs,id:\.path) { crumb in
                    Image(systemName:"chevron.right").font(.system(size:8)).foregroundStyle(.tertiary)
                    Button(crumb.name){model.currentFolder=crumb.path;model.selection=[]}.buttonStyle(.plain).lineLimit(1)
                }
                Spacer(minLength:12)
                HStack(spacing:6) {
                    Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
                    TextField(model.t("browser.search"),text:$model.search).textFieldStyle(.plain)
                    if !model.search.isEmpty {Button {model.search=""} label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.plain).foregroundStyle(.secondary)}
                }.font(.system(size:11)).padding(.horizontal,9).padding(.vertical,6).frame(width:230)
                    .background(.quaternary.opacity(0.5),in:RoundedRectangle(cornerRadius:7))
            }.font(.system(size:11)).padding(.horizontal,23).padding(.vertical,12)
            Table(model.rows.sorted(using:order),selection:$model.selection,sortOrder:$order) {
                TableColumn(model.t("table.name"),value:\.name) { row in
                    HStack(spacing:9) {
                        Image(systemName:row.icon).foregroundStyle(row.isDirectory ? Color.accentColor : Color.secondary).frame(width:17)
                        Text(row.name).lineLimit(1).truncationMode(.middle)
                        if row.isEncrypted {Image(systemName:"lock.fill").font(.system(size:8)).foregroundStyle(.secondary)}
                    }.padding(.vertical,4)
                }.width(min:220,ideal:330)
                TableColumn(model.t("table.size"),value:\.size) {row in Text(row.sizeText).monospacedDigit().foregroundStyle(.secondary)}.width(min:70,ideal:90,max:115)
                TableColumn(model.t("table.packed"),value:\.packedSize) {row in
                    Text(row.packedSize==0 ? "—" : ByteCountFormatter.string(fromByteCount:Int64(clamping:row.packedSize),countStyle:.file)).monospacedDigit().foregroundStyle(.secondary)
                }.width(min:70,ideal:90,max:110)
                TableColumn(model.t("table.modified"),value:\.modified) { row in
                    if row.modified == .distantPast {Text("—").foregroundStyle(.tertiary)} else {Text(row.modified,style:.date).foregroundStyle(.secondary)}
                }.width(min:105,ideal:125,max:150)
            }
            .tableStyle(.inset(alternatesRowBackgrounds:true))
            .contextMenu(forSelectionType:String.self) { items in
                Button(model.t("action.extractSelected")){model.presentExtract(selected:items)}.disabled(items.isEmpty)
                if items.count==1,let first=items.first,let row=model.rows.first(where:{$0.path==first}) {
                    Button(model.t(row.isDirectory ? "action.open" : "action.preview")){model.enter(row)}
                }
                Divider()
                Button(model.t("action.copyPath")) {
                    NSPasteboard.general.clearContents();NSPasteboard.general.setString(items.sorted().joined(separator:"\n"),forType:.string)
                }.disabled(items.isEmpty)
            } primaryAction: { items in
                if let first=items.first,let row=model.rows.first(where:{$0.path==first}) {model.enter(row)}
            }
            Divider()
            HStack(spacing:16) {
                Text("\(model.rows.count) "+model.t("browser.items"))
                if !model.selection.isEmpty {Text("\(model.selection.count) "+model.t("browser.selected"))}
                Spacer()
                if model.isPreviewing {ProgressView().controlSize(.mini);Text(model.t("preview.preparing"))}
                if let manifest=model.manifest {Text(manifest.backend == .sevenZip ? "7-Zip" : "libarchive").font(.system(size:10,design:.monospaced))}
            }.font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,23).padding(.vertical,11)
        }
    }
    private var header:some View {
        HStack(spacing:15) {
            Image(systemName:"doc.zipper").font(.system(size:28,weight:.light)).foregroundStyle(Color.accentColor)
                .frame(width:51,height:56).background(Color.accentColor.opacity(0.07),in:RoundedRectangle(cornerRadius:12))
            VStack(alignment:.leading,spacing:7) {
                Text(model.manifest?.source.lastPathComponent ?? "").font(.system(size:21,weight:.semibold)).lineLimit(1).truncationMode(.middle)
                HStack(spacing:10) {
                    if let manifest=model.manifest {
                        Text("\(manifest.entries.count) "+model.t("browser.entries"))
                        Text("·")
                        Text(ByteCountFormatter.string(fromByteCount:Int64(clamping:manifest.totalBytes),countStyle:.file)+" "+model.t("browser.expanded"))
                        if manifest.encrypted {Label(model.t("browser.encrypted"),systemImage:"lock")}
                    }
                }.font(.system(size:11)).foregroundStyle(.secondary)
            }
            Spacer()
            if !model.selection.isEmpty {
                Button(model.t("action.extractSelected")){model.presentExtract(selected:model.selection)}.buttonStyle(.bordered)
            }
            Button {if let source=model.manifest?.source {NSWorkspace.shared.activateFileViewerSelecting([source])}} label:{Image(systemName:"arrow.up.right.square")}.buttonStyle(.plain).help(model.t("action.reveal"))
        }.padding(24)
    }
    private var breadcrumbs:[Crumb] {
        var parts=[String]();return model.currentFolder.split(separator:"/").map{part in parts.append(String(part));return Crumb(path:parts.joined(separator:"/"),name:String(part))}
    }
    private struct Crumb {let path:String;let name:String}
}
@MainActor
struct ActivityView:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(spacing:0) {
            HStack {
                VStack(alignment:.leading,spacing:6) {
                    Text(model.t("activity.title")).font(.system(size:25,weight:.semibold,design:.rounded))
                    Text(model.t("activity.subtitle")).font(.system(size:11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.t("action.clearHistory")){model.clearHistory()}.buttonStyle(.bordered).disabled(!model.jobs.contains{$0.state.terminal})
            }.padding(27)
            Divider()
            if model.jobs.isEmpty {
                VStack(spacing:13) {
                    Image(systemName:"checklist").font(.system(size:40,weight:.ultraLight)).foregroundStyle(.tertiary)
                    Text(model.t("activity.empty")).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing:12) {
                        ForEach(model.jobs.reversed()) {job in JobCard(model:model,job:job)}
                    }.padding(24)
                }
            }
        }
    }
}
@MainActor
struct JobCard:View {
    @ObservedObject var model:AppModel
    let job:JobItem
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(spacing:12) {
                Image(systemName:stateIcon).font(.system(size:21,weight:.light)).foregroundStyle(stateColor).frame(width:32)
                VStack(alignment:.leading,spacing:5) {
                    Text(job.title).font(.system(size:13,weight:.semibold)).lineLimit(1).truncationMode(.middle)
                    HStack(spacing:7) {
                        Text(model.t(job.kind)); Text("·"); Text(model.t("state."+job.state.rawValue))
                        if !job.state.terminal {Text("·");Text(model.t(job.progress.phase))}
                    }.font(.system(size:10)).foregroundStyle(.secondary)
                }
                Spacer()
                if job.state == .running {
                    iconButton("pause",label:"action.pause"){model.pause(job.id)}
                } else if job.state == .paused {
                    iconButton("play",label:"action.resume"){model.resume(job.id)}
                }
                if !job.state.terminal {
                    iconButton("xmark",label:"action.cancel"){model.cancel(job.id)}
                } else if !job.outputs.isEmpty {
                    iconButton("folder",label:"action.reveal"){NSWorkspace.shared.activateFileViewerSelecting(job.outputs)}
                }
                if [.failed,.cancelled].contains(job.state),job.plan != nil {
                    iconButton("arrow.clockwise",label:"action.retry"){model.retry(job.id)}
                }
            }
            if !job.state.terminal {
                if let value=job.progress.fraction {ProgressView(value:value).progressViewStyle(.linear)}
                else {ProgressView().progressViewStyle(.linear)}
                HStack {
                    if let count=job.progress.entries {Text("\(count) "+model.t("browser.entries"))}
                    if let bytes=job.progress.bytes {Text(ByteCountFormatter.string(fromByteCount:Int64(clamping:bytes),countStyle:.file))}
                    Spacer()
                    if let start=job.started {
                        TimelineView(.periodic(from:.now,by:1)) { context in
                            Text(Self.duration(max(0,context.date.timeIntervalSince(start)-job.control.pausedDuration))).monospacedDigit()
                        }
                    }
                    if let value=job.progress.fraction {Text("\(Int(value*100))%").monospacedDigit().frame(width:35,alignment:.trailing)}
                }.font(.system(size:10)).foregroundStyle(.secondary)
            }
            if let key=job.errorKey {
                DisclosureGroup(model.t(key)) {
                    Text(job.errorDetail ?? "").font(.system(size:10,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(.top,6)
                }.font(.system(size:11)).foregroundStyle(.secondary)
            }
            if job.state == .interrupted {Text(model.t("activity.interrupted")).font(.system(size:11)).foregroundStyle(.secondary)}
            if let first=job.outputs.first {Text(first.path).font(.system(size:10)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)}
        }.padding(18).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:13))
            .overlay(RoundedRectangle(cornerRadius:13).strokeBorder(Color(nsColor:.separatorColor).opacity(0.35),lineWidth:0.5))
    }
    private var stateColor:Color {job.state == .succeeded ? .green : job.state == .failed ? .orange : .accentColor}
    private var stateIcon:String {job.state == .succeeded ? "checkmark.circle" : job.state == .failed ? "exclamationmark.circle" : job.kind=="job.create" ? "archivebox" : "arrow.down.doc"}
    private func iconButton(_ icon:String,label:String,action:@escaping()->Void)->some View {Button(action:action){Image(systemName:icon).frame(width:23,height:23)}.buttonStyle(.borderless).help(model.t(label)).accessibilityLabel(model.t(label))}
    private static func duration(_ seconds:TimeInterval)->String {let s=Int(seconds);return s>=3600 ? String(format:"%d:%02d:%02d",s/3600,(s/60)%60,s%60) : String(format:"%d:%02d",s/60,s%60)}
}
@MainActor
struct QuickLookContent:NSViewRepresentable {
    let url:URL
    func makeNSView(context:Context)->QLPreviewView {QLPreviewView(frame:.zero,style:.normal)!}
    func updateNSView(_ nsView:QLPreviewView,context:Context) {nsView.previewItem=url as NSURL}
}
@MainActor
struct PreviewSheet:View {
    @ObservedObject var model:AppModel
    let url:URL
    var body:some View {
        VStack(spacing:0) {
            HStack {Text(url.lastPathComponent).font(.headline);Spacer();Button(model.t("action.close")){model.dismissPreview()}.keyboardShortcut(.cancelAction)}.padding(18)
            Divider()
            QuickLookContent(url:url).frame(minWidth:720,minHeight:500)
            HStack {Label(model.t("preview.private"),systemImage:"lock");Spacer()}.font(.system(size:10)).foregroundStyle(.secondary).padding(14)
        }
    }
}
private final class DroppedURLs: @unchecked Sendable {
    private let lock=NSLock()
    private var values:[URL]=[]
    func append(_ url:URL) { lock.lock(); values.append(url); lock.unlock() }
    func snapshot()->[URL] { lock.lock(); defer {lock.unlock()}; return values }
}
enum FileDrop {
    static func read(_ providers:[NSItemProvider],completion:@escaping @MainActor ([URL])->Void) {
        let group=DispatchGroup(),files=DroppedURLs()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) {item,_ in
                defer{group.leave()}
                let url:URL?
                if let data=item as? Data {url=URL(dataRepresentation:data,relativeTo:nil)}
                else if let value=item as? URL {url=value}
                else if let value=item as? String {url=URL(string:value)}
                else {url=nil}
                if let url,url.isFileURL {files.append(url)}
            }
        }
        group.notify(queue:.global(qos:.userInitiated)) {
            let values=files.snapshot()
            Task { @MainActor in completion(values) }
        }
    }
}
#endif
