#if os(macOS)
import Foundation
import AppKit
import SwiftUI
import ArcoraCore

enum AppResources {
    static let bundle:Bundle = {
        for parent in [Bundle.main.resourceURL,Optional(Bundle.main.bundleURL)].compactMap({$0}) {
            for name in ["Arcora_Arcora.bundle","Arcora_Arcora.resources"] {
                if let value=Bundle(url:parent.appendingPathComponent(name)) { return value }
            }
        }
        return Bundle.module // SwiftPM / Xcode development resources
    }()
}
struct Preferences:Codable {
    var language="system"
    var appearance="system"
    var maxConcurrent=2
    var totalThreads=max(1,min(16,ProcessInfo.processInfo.activeProcessorCount-1))
    var memoryGiB=max(1,Int(ProcessInfo.processInfo.physicalMemory/2/1_073_741_824))
    var maxExpandedGiB=200
    var maxEntries=250_000
    var rarPath=""
    var rarLicenseAcknowledged=false
    var collision:CollisionPolicy = .rename
    var revealAfterFinish=false
}
enum SectionPage:String,CaseIterable { case workspace,activity }
enum JobState:String,Codable { case queued,running,paused,succeeded,failed,cancelled,interrupted
    var terminal:Bool { [.succeeded,.failed,.cancelled,.interrupted].contains(self) }
}
enum JobPlan: @unchecked Sendable {
    case create([URL],URL,String,CompressionOptions,Secret?,CollisionPolicy)
    case extract(URL,URL,String,Set<String>?,Secret?,Int,CollisionPolicy)
    case test(URL,Secret?,Int)
    var secret:Secret? {
        switch self { case .create(_,_,_,_,let p,_):return p; case .extract(_,_,_,_,let p,_,_):return p; case .test(_,let p,_):return p }
    }
    var threads:Int {
        switch self { case .create(_,_,_,let o,_,_):return o.threads; case .extract(_,_,_,_,_,let n,_),.test(_,_,let n):return n }
    }
    var memory:UInt64 { if case .create(_,_,_,let o,_,_)=self {return o.estimatedMemoryBytes}; return 512*1_048_576 }
    func replacingSecret(_ secret:Secret?)->JobPlan {
        switch self {
        case let .create(inputs,parent,name,options,_,collision): return .create(inputs,parent,name,options,secret,collision)
        case let .extract(input,parent,name,selection,_,threads,collision): return .extract(input,parent,name,selection,secret,threads,collision)
        case let .test(input,_,threads):return .test(input,secret,threads)
        }
    }
    func perform(_ service:ArchiveService,control:JobControl,progress:@escaping ProgressSink)throws->OperationResult {
        switch self {
        case let .create(inputs,parent,name,options,secret,collision):
            return try service.create(inputs:inputs,in:parent,name:name,options:options,password:secret,collision:collision,control:control,progress:progress)
        case let .extract(input,parent,name,selection,secret,threads,collision):
            return try service.extract(input,to:parent,name:name,selection:selection,password:secret,threads:threads,collision:collision,control:control,progress:progress)
        case let .test(input,secret,threads):return try service.test(input,password:secret,threads:threads,control:control,progress:progress)
        }
    }
}
struct JobItem:Identifiable {
    let id:UUID
    var title:String
    var kind:String
    var state:JobState
    var progress=ProgressEvent("phase.waiting")
    var created=Date()
    var started:Date?
    var finished:Date?
    var outputs:[URL]=[]
    var errorKey:String?
    var errorDetail:String?
    var plan:JobPlan?
    let control=JobControl()
    var requestedPassword=false
    var revealOnSuccess=false
    init(title:String,kind:String,plan:JobPlan) {
        id=UUID(); self.title=title; self.kind=kind; state = .queued; self.plan=plan; requestedPassword=plan.secret != nil
    }
    init(snapshot:JobSnapshot) {
        id=snapshot.id; title=snapshot.title; kind=snapshot.kind
        state=snapshot.state.terminal ? snapshot.state : .interrupted
        created=snapshot.created; finished=snapshot.finished; outputs=snapshot.outputs
    }
}
struct JobSnapshot:Codable {
    let id:UUID,title:String,kind:String,state:JobState,created:Date,finished:Date?,outputs:[URL]
    init(_ item:JobItem) {
        id=item.id; title=item.title; kind=item.kind; state=item.state; created=item.created; finished=item.finished; outputs=item.outputs
    }
}
struct UIError:Identifiable { let id=UUID(); let title:String; let detail:String }
struct ArchiveRow:Identifiable,Sendable {
    var path:String,name:String
    var size:UInt64,packedSize:UInt64
    var modified:Date
    var isDirectory:Bool,isEncrypted:Bool
    var id:String { path }
    var icon:String { isDirectory ? "folder" : "doc" }
    var sizeText:String { isDirectory ? "—" : ByteCountFormatter.string(fromByteCount:Int64(clamping:size),countStyle:.file) }
}

@MainActor
final class AppModel:ObservableObject {
    @Published var preferences:Preferences { didSet { savePreferences() } }
    @Published var page:SectionPage = .workspace
    @Published var manifest:ArchiveManifest? { didSet { rebuildRows() } }
    @Published var isLoading=false
    @Published var currentFolder="" { didSet { rebuildRows() } }
    @Published var search="" { didSet { rebuildRows() } }
    @Published var selection=Set<String>()
    @Published var recents:[URL]=[]
    @Published var jobs:[JobItem]=[]
    @Published var showCreate=false
    @Published var showExtraction=false
    @Published var showPassword=false
    @Published var showGuide=false
    @Published var error:UIError?
    @Published var previewURL:URL?
    @Published var isPreviewing=false
    @Published private(set) var rarLicenseState:RARLicenseState = .missing
    @Published private(set) var checkingRARLicense=false
    @Published private(set) var importingRARPackage=false
    @Published private(set) var rarSetupError:String?
    @Published private var engineLocations=EngineLocations.discover()
    let rarLicenseStore=RARLicenseStore()
    let rarInstallationStore=RARInstallationStore()
    var createSources:[URL]=[]
    var createFormat:ArchiveFormat = .sevenZip
    var reopenMainWindow:(()->Void)?
    private var finderRequests=[FinderCompressionRequest]()
    private var handlingFinderRequest=false
    private var finderRequestRevision=UUID()
    var extractionSelection:Set<String>?
    private var currentPassword:Secret?
    private var inspectionControl:JobControl?
    private var previewControl:JobControl?
    private var rowsTask:Task<[ArchiveRow],Never>?
    private var rowsRevision=UUID()
    @Published private(set) var rows:[ArchiveRow]=[]
    private var passwordContinuation:((Secret)->Void)?
    private var archiveRevision=UUID()
    private let storage:URL
    private let previews:URL

    init() {
        let defaults=UserDefaults.standard
        preferences=defaults.data(forKey:"Arcora.preferences").flatMap{try? JSONDecoder().decode(Preferences.self,from:$0)} ?? Preferences()
        storage=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Arcora",isDirectory:true)
        previews=FileManager.default.temporaryDirectory.appendingPathComponent("Arcora-previews-"+UUID().uuidString,isDirectory:true)
        try? FileManager.default.createDirectory(at:storage,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try? FileManager.default.createDirectory(at:previews,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        recents=(defaults.stringArray(forKey:"Arcora.recents") ?? []).map{URL(fileURLWithPath:$0)}
        if let data=try? Data(contentsOf:storage.appendingPathComponent("history.json")),let history=try? JSONDecoder().decode([JobSnapshot].self,from:data) {
            jobs=history.suffix(100).map(JobItem.init(snapshot:))
        }
        refreshRARLicense()
    }
    var locale:Locale { Locale(identifier:languageCode) }
    var languageCode:String {
        let raw=preferences.language=="system" ? (Locale.preferredLanguages.first ?? "en") : preferences.language
        return raw.hasPrefix("zh") ? "zh-Hans" : raw.hasPrefix("ja") ? "ja" : "en"
    }
    func t(_ key:String)->String {
        let resources=AppResources.bundle
        // SwiftPM lowercases lproj names (zh-hans); Bundle lookup is case-sensitive.
        let localization=resources.localizations.first{$0.caseInsensitiveCompare(languageCode) == .orderedSame} ?? "en"
        guard let path=resources.path(forResource:localization,ofType:"lproj"),let bundle=Bundle(path:path) else { return key }
        return bundle.localizedString(forKey:key,value:key,table:nil)
    }
    var limits:SafetyLimits {
        var value=SafetyLimits()
        value.maxMemoryBytes=UInt64(max(1,preferences.memoryGiB))*1_073_741_824
        value.maxExpandedBytes=UInt64(max(1,preferences.maxExpandedGiB))*1_073_741_824
        value.maxEntries=max(1000,preferences.maxEntries)
        return value
    }
    var engines:EngineLocations {
        // The optional RAR original is imported locally; no PATH/Homebrew configuration is needed.
        var value=engineLocations
        value.rarLicenseDirectory=rarLicenseStore.root
        return value
    }
    var canCreateRAR:Bool {engines.rar != nil && (!engines.rarRequiresLicense || rarLicenseState == .verified) && !checkingRARLicense && !importingRARPackage}
    func importRARPackage(_ file:URL) {
        guard !hasCodecWork,!checkingRARLicense,!importingRARPackage else {return}
        importingRARPackage=true;rarSetupError=nil
        let store=rarInstallationStore
        Task {
            let result=await Task.detached(priority:.userInitiated) {Result {try store.importPackage(from:file)}}.value
            self.importingRARPackage=false;self.engineLocations=EngineLocations.discover()
            if case .failure(let error)=result {self.rarSetupError=error.localizedDescription}
            self.refreshRARLicense()
        }
    }
    func removeRARPackage() {
        guard !hasCodecWork,!checkingRARLicense,!importingRARPackage else {return}
        do {
            try rarInstallationStore.moveImportedCopyToTrash()
            engineLocations=EngineLocations.discover();rarLicenseState = .missing;rarSetupError=nil
        } catch {rarSetupError=error.localizedDescription}
    }
    func refreshRARLicense() {
        guard !checkingRARLicense,!importingRARPackage else {return}
        engineLocations=EngineLocations.discover()
        guard let engine=engines.rar else {rarLicenseState = .missing;processFinderRequests();return}
        checkingRARLicense=true
        let store=rarLicenseStore
        Task {
            let state=await Task.detached(priority:.utility) {store.status(using:engine)}.value
            self.rarLicenseState=state;self.checkingRARLicense=false
            self.processFinderRequests()
        }
    }
    func importRARLicense(_ file:URL,rightsAcknowledged:Bool) {
        guard !hasCodecWork,!checkingRARLicense,!importingRARPackage,let engine=try? engines.requireRAR() else {return}
        checkingRARLicense=true;rarSetupError=nil
        let store=rarLicenseStore
        Task {
            let result=await Task.detached(priority:.userInitiated) {Result {try store.importKey(from:file,using:engine,rightsAcknowledged:rightsAcknowledged)}}.value
            self.checkingRARLicense=false
            if case .failure(let error)=result {self.rarSetupError=error.localizedDescription}
            self.refreshRARLicense()
        }
    }
    func removeRARLicense() {
        guard !hasCodecWork,!checkingRARLicense,!importingRARPackage else {return}
        do {try rarLicenseStore.moveImportedCopyToTrash();rarLicenseState = .missing}
        catch {report(error)}
    }
    var service:ArchiveService { ArchiveService(engines:engines,limits:limits) }
    var activeJobs:[JobItem] { jobs.filter{!$0.state.terminal} }
    // Undispatched Finder requests have not captured engine state. They must not
    // lock RAR setup while the user resolves a pending request's missing engine.
    var hasCodecWork:Bool {isLoading || !activeJobs.isEmpty || isPreviewing || handlingFinderRequest}
    var hasPendingWork:Bool {hasCodecWork || !finderRequests.isEmpty}
    var hasRunningWork:Bool { isLoading || isPreviewing || handlingFinderRequest || jobs.contains{ $0.state == .running || $0.state == .paused } }
    private func rebuildRows() {
        rowsTask?.cancel()
        let revision=UUID(); rowsRevision=revision
        guard let manifest else { rows=[]; return }
        let entries=manifest.entries,folder=currentFolder,query=search
        let work=Task.detached(priority:.userInitiated) { Self.makeRows(entries:entries,currentFolder:folder,search:query) }
        rowsTask=work
        Task { let value=await work.value; if self.rowsRevision==revision { self.rows=value } }
    }
    nonisolated private static func makeRows(entries:[ArchiveEntry],currentFolder:String,search:String)->[ArchiveRow] {
        var map=[String:ArchiveRow]()
        let prefix=currentFolder.isEmpty ? "" : currentFolder+"/"
        let query=search.trimmingCharacters(in:.whitespacesAndNewlines)
        for entry in entries where entry.path != "." {
            if Task.isCancelled { return [] }
            if !query.isEmpty {
                guard entry.path.localizedStandardContains(query) else { continue }
                map[entry.path]=ArchiveRow(path:entry.path,name:entry.path,size:entry.size,packedSize:entry.packedSize ?? 0,
                                          modified:entry.modified ?? .distantPast,isDirectory:entry.isDirectory,isEncrypted:entry.isEncrypted)
                continue
            }
            guard entry.path.hasPrefix(prefix) else {continue}
            let rest=String(entry.path.dropFirst(prefix.count))
            guard !rest.isEmpty else {continue}
            if let slash=rest.firstIndex(of:"/") {
                let first=String(rest[..<slash]),path=prefix+first
                if map[path]==nil { map[path]=ArchiveRow(path:path,name:first,size:0,packedSize:0,modified:.distantPast,isDirectory:true,isEncrypted:false) }
            } else {
                map[entry.path]=ArchiveRow(path:entry.path,name:rest,size:entry.size,packedSize:entry.packedSize ?? 0,
                                          modified:entry.modified ?? .distantPast,isDirectory:entry.isDirectory,isEncrypted:entry.isEncrypted)
            }
        }
        return Array(map.values)
    }
    func chooseArchive() {
        let panel=NSOpenPanel(); panel.canChooseDirectories=false; panel.allowsMultipleSelection=false
        panel.message=t("open.message"); panel.prompt=t("action.open")
        if panel.runModal() == .OK,let url=panel.url { open(url) }
    }
    func open(_ source:URL,password:Secret?=nil) {
        inspectionControl?.cancel()
        currentPassword?.clear(); currentPassword=password?.copy()
        let control=JobControl(); inspectionControl=control
        let service=self.service,secret=password?.copy()
        isLoading=true; page = .workspace
        let revision=UUID(); archiveRevision=revision
        Task {
            let result=await Task.detached(priority:.userInitiated) { () -> Result<ArchiveManifest,Error> in
                defer{secret?.clear()}
                return Result { try service.inspect(source,password:secret,control:control) }
            }.value
            guard self.archiveRevision==revision else { return }
            self.isLoading=false
            switch result {
            case .success(let value):
                self.manifest=value; self.currentFolder=""; self.search=""; self.selection=[]
                self.recents.removeAll{$0==value.source}; self.recents.insert(value.source,at:0); self.recents=Array(self.recents.prefix(12))
                UserDefaults.standard.set(self.recents.map{$0.path},forKey:"Arcora.recents")
            case .failure(let error):
                if let e=error as? ArchiveError,e == .passwordRequired || e == .wrongPassword {
                    self.askPassword { [weak self] in self?.open(source,password:$0) }
                } else if (error as? ArchiveError) != .cancelled { self.report(error) }
            }
        }
    }
    func closeArchive() {
        archiveRevision=UUID(); inspectionControl?.cancel(); isLoading=false
        manifest=nil; currentFolder=""; search=""; selection=[]; currentPassword?.clear(); currentPassword=nil
    }
    func presentCreate(_ files:[URL]=[],format:ArchiveFormat = .sevenZip) {
        createSources=files;createFormat=format;showCreate=true
    }
    var hasPresentedDialog:Bool {showCreate || showExtraction || showPassword || showGuide || previewURL != nil || error != nil}
    func receiveFinderRequest(_ request:FinderCompressionRequest) {
        guard finderRequests.count<32 else {report(ArchiveError.resourceLimit(t("finder.queueFull")));return}
        finderRequests.append(request)
        processFinderRequests()
    }
    func processFinderRequests() {
        guard !hasPresentedDialog,!handlingFinderRequest,let request=finderRequests.first else {return}
        if request.action == .rar && (checkingRARLicense || importingRARPackage) {return}
        finderRequests.removeFirst();handlingFinderRequest=true
        let revision=finderRequestRevision
        // Return to the Services caller before filesystem work or destination UI.
        Task { @MainActor in
            defer {self.handlingFinderRequest=false;self.processFinderRequests()}
            do {
                let plan=try await Task.detached(priority:.userInitiated) {try FinderCompressionPlan(request:request)}.value
                guard self.finderRequestRevision==revision else {return}
                if self.hasPresentedDialog {self.finderRequests.insert(request,at:0);return}
                guard let format=request.action.format else {self.presentCreate(plan.files);return}
                if format == .rar && !self.canCreateRAR {
                    self.presentCreate(plan.files,format:.rar);return
                }
                let directory:URL
                if let sibling=plan.siblingDirectory,FileManager.default.isWritableFile(atPath:sibling.path) {directory=sibling}
                else {
                    let initial=plan.siblingDirectory ?? FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask)[0]
                    guard let selected=FolderPicker.choose(message:self.t("finder.chooseDestination"),initial:initial) else {return}
                    directory=selected
                }
                let options=FinderCompressionPlan.quickOptions(format:format,threads:self.preferences.totalThreads)
                try options.validate(hasPassword:false)
                self.enqueue(title:plan.name+"."+format.rawValue,kind:"job.create",
                    plan:.create(plan.files,directory,plan.name,options,nil,.rename),revealOnSuccess:true)
                self.page = .activity
            } catch {self.report(error)}
        }
    }
    func handleDrop(_ files:[URL]) {
        guard !files.isEmpty else{return}
        if files.count==1,let file=files.first,
           (try? file.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) != true {
            let ext=file.pathExtension.lowercased()
            let known=["zip","7z","rar","tar","gz","bz2","xz","zst","tgz","tbz2","txz","iso","dmg","cab","wim","esd","vhd","vhdx","xar","cpio","ar","deb","rpm","lzh","lha","chm","001"]
            if known.contains(ext) || ext.range(of:"^[rz][0-9]{2,}$",options:.regularExpression) != nil || Int(ext) != nil {open(file);return}
        }
        presentCreate(files)
    }
    func askPassword(_ body:@escaping (Secret)->Void) { passwordContinuation=body; showPassword=true }
    func providePassword(_ text:String) {
        do {
            let secret=try Secret(text)
            let callback=passwordContinuation; passwordContinuation=nil; showPassword=false
            DispatchQueue.main.async { callback?(secret) }
        } catch { report(error) }
    }
    func dismissPassword() { showPassword=false; passwordContinuation=nil }
    func presentExtract(selected:Set<String>?=nil) {
        guard let manifest,!hasPresentedDialog else{return}
        extractionSelection=selected
        if manifest.encrypted && currentPassword==nil {
            askPassword { [weak self] secret in self?.currentPassword=secret; self?.showExtraction=true }
        } else { showExtraction=true }
    }
    func submitExtract(parent:URL,name:String) {
        guard showExtraction,let manifest else{return}
        // Consume the presentation before enqueueing, so repeated activation
        // cannot schedule the same sheet's extraction twice.
        showExtraction=false
        let threads=max(1,min(4,preferences.totalThreads))
        enqueue(title:manifest.source.lastPathComponent,kind:"job.extract",plan:.extract(manifest.source,parent,name,extractionSelection,currentPassword?.copy(),threads,preferences.collision))
        page = .activity
    }
    func requestTest() {
        guard let manifest else{return}
        if manifest.encrypted && currentPassword==nil {
            askPassword { [weak self] secret in self?.currentPassword=secret; self?.requestTest() };return
        }
        enqueue(title:manifest.source.lastPathComponent,kind:"job.test",plan:.test(manifest.source,currentPassword?.copy(),max(1,min(4,preferences.totalThreads))))
        page = .activity
    }
    func submitCreate(inputs:[URL],parent:URL,name:String,options:CompressionOptions,password:String) {
        do {
            let secret=password.isEmpty ? nil : try Secret(password)
            try options.validate(hasPassword:secret != nil)
            guard options.threads<=preferences.totalThreads,options.estimatedMemoryBytes<=limits.maxMemoryBytes else {
                throw ArchiveError.resourceLimit(t("compression.memoryHint"))
            }
            enqueue(title:name+"."+options.format.rawValue,kind:"job.create",plan:.create(inputs,parent,name,options,secret,preferences.collision))
            showCreate=false; page = .activity
        } catch { report(error) }
    }
    private func enqueue(title:String,kind:String,plan:JobPlan,revealOnSuccess:Bool=false) {
        var job=JobItem(title:title,kind:kind,plan:plan);job.revealOnSuccess=revealOnSuccess
        jobs.append(job); persistHistory(); pump()
    }
    func pump() {
        let running=jobs.filter{$0.state == .running || $0.state == .paused}
        guard running.count<max(1,preferences.maxConcurrent) else{return}
        let usedThreads=running.reduce(0){$0+($1.plan?.threads ?? 1)}
        let usedMemory=running.reduce(UInt64(0)){$0+($1.plan?.memory ?? 0)}
        guard let index=jobs.firstIndex(where:{$0.state == .queued}),let plan=jobs[index].plan else{return}
        if plan.threads>preferences.totalThreads || plan.memory>limits.maxMemoryBytes {
            jobs[index].state = .failed; jobs[index].errorKey="error.limit"; jobs[index].errorDetail=t("compression.memoryHint")
            jobs[index].plan?.secret?.clear(); persistHistory(); pump();return
        }
        guard usedThreads+plan.threads<=preferences.totalThreads,usedMemory+plan.memory<=limits.maxMemoryBytes else{return}
        let id=jobs[index].id,control=jobs[index].control,service=self.service
        jobs[index].state = .running; jobs[index].started=Date(); persistHistory()
        let receiveProgress:@MainActor @Sendable (ProgressEvent)->Void = { [weak self] value in
            if let self,let i=self.jobs.firstIndex(where:{$0.id==id}),!self.jobs[i].state.terminal {self.jobs[i].progress=value}
        }
        Task {
            let result=await Task.detached(priority:.userInitiated) { ()->Result<OperationResult,Error> in
                defer{plan.secret?.clear()}
                return Result { try plan.perform(service,control:control,progress:{ value in
                    Task { @MainActor in receiveProgress(value) }
                }) }
            }.value
            guard let i=self.jobs.firstIndex(where:{$0.id==id}) else{return}
            self.jobs[i].finished=Date()
            switch result {
            case .success(let output):
                self.jobs[i].state = .succeeded; self.jobs[i].outputs=output.outputs; self.jobs[i].progress=ProgressEvent("phase.complete",fraction:1)
                if (self.preferences.revealAfterFinish || self.jobs[i].revealOnSuccess),!output.outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(output.outputs) }
            case .failure(let error):
                self.jobs[i].state=(error as? ArchiveError) == .cancelled ? .cancelled : .failed
                self.jobs[i].errorKey=(error as? ArchiveError)?.localizationKey ?? "error.io"
                self.jobs[i].errorDetail=error.localizedDescription
            }
            // Keep a non-secret retry plan, never a previous password.
            self.jobs[i].plan=plan.replacingSecret(nil)
            self.persistHistory(); self.pump()
        }
        pump()
    }
    func pause(_ id:UUID) { guard let i=jobs.firstIndex(where:{$0.id==id}),jobs[i].state == .running else{return}; jobs[i].control.pause();jobs[i].state = .paused;persistHistory() }
    func resume(_ id:UUID) { guard let i=jobs.firstIndex(where:{$0.id==id}),jobs[i].state == .paused else{return}; jobs[i].control.resume();jobs[i].state = .running;persistHistory() }
    func cancel(_ id:UUID) {
        guard let i=jobs.firstIndex(where:{$0.id==id}),!jobs[i].state.terminal else{return}
        jobs[i].control.cancel()
        if jobs[i].state == .queued { jobs[i].state = .cancelled; jobs[i].plan?.secret?.clear(); jobs[i].plan=jobs[i].plan?.replacingSecret(nil);persistHistory();pump() }
    }
    func cancelAll() {
        finderRequestRevision=UUID();finderRequests.removeAll()
        inspectionControl?.cancel(); previewControl?.cancel(); for job in jobs where !job.state.terminal {cancel(job.id)}
    }
    func retry(_ id:UUID) {
        guard let job=jobs.first(where:{$0.id==id}),let plan=job.plan else{return}
        if job.requestedPassword || job.errorKey=="error.passwordRequired" || job.errorKey=="error.wrongPassword" {
            askPassword { [weak self] secret in self?.enqueue(title:job.title,kind:job.kind,plan:plan.replacingSecret(secret),revealOnSuccess:job.revealOnSuccess) }
        } else { enqueue(title:job.title,kind:job.kind,plan:plan,revealOnSuccess:job.revealOnSuccess) }
    }
    func clearHistory() { jobs.removeAll{$0.state.terminal};persistHistory() }
    func clearRecents() { recents=[];UserDefaults.standard.removeObject(forKey:"Arcora.recents") }
    func enter(_ row:ArchiveRow) { if row.isDirectory {currentFolder=row.path;search="";selection=[]} else {preview(row)} }
    func preview(_ row:ArchiveRow) {
        guard let manifest,!row.isDirectory,!isPreviewing else{return}
        guard row.size<=100*1_048_576 else {report(ArchiveError.resourceLimit(t("preview.limit")));return}
        if manifest.encrypted && currentPassword==nil {askPassword{[weak self] secret in self?.currentPassword=secret;self?.preview(row)};return}
        let service=self.service,secret=currentPassword?.copy(),parent=previews,control=JobControl(),source=manifest.source
        let limit=limits.maxExpandedBytes
        isPreviewing=true; previewControl=control
        Task {
            let result=await Task.detached(priority:.userInitiated) { ()->Result<URL,Error> in
                defer{secret?.clear()}
                return Result {
                    let output=try service.extract(source,to:parent,name:UUID().uuidString,selection:[row.path],password:secret,control:control)
                    guard let root=output.outputs.first else{throw ArchiveError.io("No preview output.")}
                    let target=root.appendingPathComponent(row.path)
                    guard (try target.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<=min(Int(clamping:limit),100*1_048_576) else{throw ArchiveError.resourceLimit("Preview limit exceeded.")}
                    return target
                }
            }.value
            self.isPreviewing=false; self.previewControl=nil
            switch result {case .success(let url):self.previewURL=url;case .failure(let error): if (error as? ArchiveError) != .cancelled { self.report(error) }; self.dismissPreview()}
        }
    }
    func dismissPreview() {
        previewURL=nil
        // Delete only this process's private preview root; never the source or destination.
        if let items=try? FileManager.default.contentsOfDirectory(at:previews,includingPropertiesForKeys:nil) { for item in items {try? FileManager.default.removeItem(at:item)} }
    }
    func prepareToQuit() { currentPassword?.clear(); rowsTask?.cancel(); dismissPreview(); try? FileManager.default.removeItem(at:previews) }
    func report(_ e:Error) {error=UIError(title:t((e as? ArchiveError)?.localizationKey ?? "error.io"),detail:e.localizedDescription)}
    private func savePreferences() {
        if let data=try? JSONEncoder().encode(preferences) {UserDefaults.standard.set(data,forKey:"Arcora.preferences")}
    }
    private func persistHistory() {
        let snapshots=jobs.suffix(100).map(JobSnapshot.init)
        if let data=try? JSONEncoder().encode(snapshots) {try? data.write(to:storage.appendingPathComponent("history.json"),options:.atomic)}
    }
}
#endif
