#if os(macOS)
import SwiftUI
import AppKit
import ArcoraCore

@MainActor
struct SettingsView:View {
    @ObservedObject var model:AppModel
    private struct LicenseSelection:Identifiable {let url:URL;var id:URL {url}}
    @State private var licenseFile:LicenseSelection?
    @State private var showRemoveEngine=false
    var body:some View {
        TabView {
            general.tabItem{Label(model.t("settings.general"),systemImage:"slider.horizontal.3")}
            performance.tabItem{Label(model.t("settings.performance"),systemImage:"cpu")}
            engines.tabItem{Label(model.t("settings.engines"),systemImage:"shippingbox")}
            about.tabItem{Label(model.t("settings.about"),systemImage:"info.circle")}
        }.padding(16).frame(width:650,height:660)
        .sheet(item:$licenseFile) {selection in RARLicenseImportSheet(model:model,file:selection.url)}
        .confirmationDialog(model.t("rar.removeEngineNote"),isPresented:$showRemoveEngine,titleVisibility:.visible) {
            Button(model.t("rar.removeEngine"),role:.destructive){model.removeRARPackage()}
        }
    }
    private var general:some View {
        Form {
            Section(model.t("settings.interface")) {
                Picker(model.t("settings.language"),selection:$model.preferences.language) {
                    Text(model.t("settings.system")).tag("system");Text("简体中文").tag("zh-Hans");Text("English").tag("en");Text("日本語").tag("ja")
                }
                Picker(model.t("settings.appearance"),selection:$model.preferences.appearance) {
                    Text(model.t("settings.system")).tag("system");Text(model.t("settings.light")).tag("light");Text(model.t("settings.dark")).tag("dark")
                }
            }
            Section(model.t("settings.behavior")) {
                Picker(model.t("settings.collision"),selection:$model.preferences.collision) {
                    Text(model.t("collision.rename")).tag(CollisionPolicy.rename);Text(model.t("collision.fail")).tag(CollisionPolicy.fail)
                }
                Toggle(model.t("settings.reveal"),isOn:$model.preferences.revealAfterFinish)
            }
            Section(model.t("settings.privacy")) {
                Text(model.t("privacy.details")).font(.system(size:11)).foregroundStyle(.secondary)
                HStack {Button(model.t("action.clearRecents")){model.clearRecents()};Button(model.t("action.clearHistory")){model.clearHistory()}}
            }
        }.formStyle(.grouped)
    }
    private var performance:some View {
        Form {
            Section(model.t("settings.scheduler")) {
                Stepper(value:$model.preferences.maxConcurrent,in:1...8){LabeledContent(model.t("settings.parallelJobs"),value:"\(model.preferences.maxConcurrent)")}
                Stepper(value:$model.preferences.totalThreads,in:1...max(1,ProcessInfo.processInfo.activeProcessorCount)){LabeledContent(model.t("settings.cpuThreads"),value:"\(model.preferences.totalThreads)")}
                Stepper(value:$model.preferences.memoryGiB,in:1...max(1,Int(ProcessInfo.processInfo.physicalMemory/1_073_741_824)-1)){LabeledContent(model.t("settings.memory"),value:"\(model.preferences.memoryGiB) GiB")}
                Text(model.t("settings.resourceNote")).font(.system(size:11)).foregroundStyle(.secondary)
            }.disabled(model.hasPendingWork)
            Section(model.t("settings.safety")) {
                Stepper(value:$model.preferences.maxExpandedGiB,in:1...16384,step:50){LabeledContent(model.t("settings.expandedLimit"),value:"\(model.preferences.maxExpandedGiB) GiB")}
                Stepper(value:$model.preferences.maxEntries,in:1000...2_000_000,step:10000){LabeledContent(model.t("settings.entryLimit"),value:"\(model.preferences.maxEntries)")}
                Text(model.t("settings.safetyNote")).font(.system(size:11)).foregroundStyle(.secondary)
            }.disabled(model.hasPendingWork)
        }.formStyle(.grouped)
        .onDisappear {model.pump()}
    }
    private var engines:some View {
        Form {
            Section("7-Zip 26.03") {
                LabeledContent(model.t("engine.status"),value:model.t(model.engines.sevenZip==nil ? "engine.unavailable" : "engine.ready"))
                Text(model.engines.sevenZip?.path ?? model.t("engine.missing")).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Section("libarchive") {
                Text(NativeArchive.version).font(.system(size:11,design:.monospaced))
                Text(model.t("engine.nativeNote")).font(.system(size:11)).foregroundStyle(.secondary)
            }
            Section(model.t("rar.title")) {
                if model.engines.rarIsBundled {
                    LabeledContent(model.t("engine.status"),value:model.t("rar.engineBundled"))
                    Text(model.t("rar.localBundleNote")).font(.system(size:11)).foregroundStyle(.secondary)
                } else {
                Text(model.t("rar.setupNote")).font(.system(size:11)).foregroundStyle(.secondary)
                VStack(alignment:.leading,spacing:7) {
                    Text(model.t("rar.stepDownload")).fontWeight(.medium)
                    HStack {
                        Link(model.t("rar.officialDownload"),destination:RARPackage.current.downloadURL)
                        Text(RARPackage.current.architecture=="arm64" ? "Apple Silicon · arm64" : "Intel · x86_64").foregroundStyle(.secondary)
                    }
                    Text(RARPackage.current.filename).font(.system(size:10,design:.monospaced)).textSelection(.enabled)
                    Text(model.t("rar.browserDownloadNote")).font(.system(size:10)).foregroundStyle(.secondary)
                }.font(.system(size:12))
                VStack(alignment:.leading,spacing:7) {
                    Text(model.t("rar.stepImport")).fontWeight(.medium)
                    HStack {
                        Button(model.t("rar.importPackage")){selectPackage()}
                        if model.importingRARPackage {ProgressView().controlSize(.small);Text(model.t("rar.importingPackage"))}
                        else {Text(model.t(model.engines.rar == nil ? "engine.unavailable" : "rar.engineReady")).foregroundStyle(.secondary)}
                        if model.engines.rarInstallationDirectory != nil {
                            Button(model.t("rar.removeEngine")){showRemoveEngine=true}
                        }
                    }.disabled(model.importingRARPackage || model.checkingRARLicense)
                    Text(model.t("rar.packageVerificationNote")).font(.system(size:10)).foregroundStyle(.secondary)
                }.font(.system(size:12))
                }
                VStack(alignment:.leading,spacing:7) {
                    Text(model.t(model.engines.rarIsBundled ? "rar.importLicense" : "rar.stepLicense")).fontWeight(.medium)
                    Text(model.t(model.engines.rarRequiresLicense ? "rar.customerLicenseNote" : "rar.localLicenseNote")).font(.system(size:11)).foregroundStyle(.secondary)
                    LabeledContent(model.t("rar.licenseStatus"),value:model.t(licenseStatusKey))
                    HStack {
                        Button(model.t("rar.importLicense")){selectLicense()}
                        Button(model.t("rar.recheckLicense")){model.refreshRARLicense()}
                        if model.rarLicenseState != .missing {Button(model.t("rar.removeLicense")){model.removeRARLicense()}}
                    }.disabled(model.engines.rar == nil || model.checkingRARLicense || model.importingRARPackage)
                    Text(model.t("rar.licensePrivacy")).font(.system(size:10)).foregroundStyle(.secondary)
                    if model.engines.rar != nil && !model.engines.rarRequiresLicense {Text(model.t("rar.localEvaluation")).font(.system(size:11)).foregroundStyle(.orange)}
                }.font(.system(size:12))
                if let error=model.rarSetupError {
                    Text(error).font(.system(size:11)).foregroundStyle(.red).textSelection(.enabled)
                }
                HStack {
                    Link(model.t("rar.purchaseLicense"),destination:URL(string:"https://www.rarlab.com/registration.php")!)
                    Link(model.t("rar.licenseTerms"),destination:URL(string:"https://www.rarlab.com/license.htm")!)
                }.font(.system(size:11))
            }.disabled(model.hasPendingWork)
        }.formStyle(.grouped)
    }
    private var licenseStatusKey:String {
        if model.checkingRARLicense {return "rar.checkingLicense"}
        if !model.engines.rarRequiresLicense && model.rarLicenseState == .missing {return "rar.license.localEvaluation"}
        return model.rarLicenseState.localizationKey
    }
    private var about:some View {
        VStack(spacing:17) {
            Spacer(minLength:12)
            Image(systemName:"archivebox.fill").font(.system(size:52,weight:.light)).foregroundStyle(Color.accentColor)
            Text("Arcora").font(.system(size:30,weight:.semibold,design:.rounded))
            Text((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0")+" · Arcora").font(.system(size:11)).foregroundStyle(.secondary)
            Text(model.t("app.tagline")).foregroundStyle(.secondary)
            Divider().padding(.horizontal,70)
            Text(model.t("about.description")).font(.system(size:12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5).padding(.horizontal,35)
            Text(model.t("about.license")).font(.system(size:10)).foregroundStyle(.tertiary).multilineTextAlignment(.center).padding(.horizontal,30)
            Button(model.t("about.notices")) {
                let url=Bundle.main.resourceURL?.appendingPathComponent("ThirdParty")
                if let url,FileManager.default.fileExists(atPath:url.path){NSWorkspace.shared.open(url)}
            }
            Spacer()
        }
    }
    private func selectLicense() {
        let panel=NSOpenPanel();panel.canChooseFiles=true;panel.canChooseDirectories=false;panel.allowsMultipleSelection=false;panel.message=model.t("rar.selectLicense")
        if panel.runModal() == .OK,let url=panel.url {licenseFile=LicenseSelection(url:url)}
    }
    private func selectPackage() {
        let panel=NSOpenPanel();panel.canChooseFiles=true;panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
        panel.message=model.t("rar.selectPackage")+"\n"+RARPackage.current.filename
        if panel.runModal() == .OK,let url=panel.url {model.importRARPackage(url)}
    }
}

@MainActor
private struct RARLicenseImportSheet:View {
    @ObservedObject var model:AppModel
    let file:URL
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledged=false
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text(model.t("rar.importLicense")).font(.title2)
            Text(file.lastPathComponent).font(.system(.body,design:.monospaced))
            Text(model.t("rar.customerLicenseNote"))
            Toggle(model.t("rar.customerRights"),isOn:$acknowledged)
            Text(model.t("rar.licensePrivacy")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Link(model.t("rar.licenseTerms"),destination:URL(string:"https://www.rarlab.com/license.htm")!)
                Spacer()
                Button(model.t("action.cancel")){dismiss()}
                Button(model.t("rar.importAndVerify")){model.importRARLicense(file,rightsAcknowledged:acknowledged);dismiss()}
                    .buttonStyle(.borderedProminent).disabled(!acknowledged)
            }
        }.padding(24).frame(width:530)
    }
}
@MainActor
struct GuideView:View {
    @ObservedObject var model:AppModel
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        VStack(spacing:0) {
            SheetHeading(icon:"book.closed",title:model.t("guide.title"),subtitle:"Arcora · macOS")
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    ForEach(["start","formats","rar","parts","password","threads","safety","build"],id:\.self) {section in
                        VStack(alignment:.leading,spacing:8) {
                            Text(model.t("guide."+section+".title")).font(.system(size:13,weight:.semibold))
                            Text(model.t("guide."+section+".body")).font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                        }
                    }
                }.padding(28)
            }
            Divider()
            HStack {Spacer();Button(model.t("action.close")){dismiss()}.keyboardShortcut(.cancelAction)}.padding(17)
        }.frame(width:680,height:690)
    }
}
#endif
