#if os(macOS)
import SwiftUI
import AppKit
import ArcoraCore

@main
struct ArcoraApp: App {
    @StateObject private var model=AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Arcora") {
            MainWindow(model:model)
                .environment(\.locale,model.locale)
                .preferredColorScheme(model.preferences.appearance == "dark" ? .dark : model.preferences.appearance == "light" ? .light : nil)
                .onAppear { delegate.model=model; NSApp.servicesProvider=delegate }
                .onOpenURL { model.open($0) }
        }
        .defaultSize(width:1080,height:730)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing:.newItem) {
                Button(model.t("action.new")){ model.presentCreate() }.keyboardShortcut("n")
                Button(model.t("action.open")){ model.chooseArchive() }.keyboardShortcut("o")
            }
            CommandMenu(model.t("menu.archive")) {
                Button(model.t("action.extract")){ model.presentExtract() }.keyboardShortcut("e").disabled(model.manifest==nil)
                Button(model.t("action.test")){ model.requestTest() }.keyboardShortcut("t").disabled(model.manifest==nil)
                Divider()
                Button(model.t("action.closeArchive")){ model.closeArchive() }.disabled(model.manifest==nil)
            }
            CommandGroup(replacing:.help) {
                Button(model.t("action.guide")){ model.showGuide=true }
            }
        }
        Settings { SettingsView(model:model).environment(\.locale,model.locale) }
    }
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model:AppModel?
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard model.hasPendingWork else { model.prepareToQuit(); return .terminateNow }
        let alert=NSAlert(); alert.messageText=model.t("quit.title"); alert.informativeText=model.t("quit.detail")
        alert.addButton(withTitle:model.t("quit.cancelJobs")); alert.addButton(withTitle:model.t("action.back"))
        if alert.runModal() == .alertFirstButtonReturn {
            model.cancelAll()
            // Wait asynchronously for worker termination and transactional cleanup.
            Task { while model.hasRunningWork { try? await Task.sleep(nanoseconds:100_000_000) }; model.prepareToQuit(); NSApp.reply(toApplicationShouldTerminate:true) }
            return .terminateLater
        }
        return .terminateCancel
    }
    @objc func compressFiles(_ pasteboard:NSPasteboard,userData:String?,error:AutoreleasingUnsafeMutablePointer<NSString>) {
        if let urls=pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],!urls.isEmpty {
            model?.presentCreate(urls); NSApp.activate(ignoringOtherApps:true)
        }
    }
}
#else
import Foundation
@main struct UnsupportedPlatform { static func main() { print("Arcora's graphical interface requires macOS 14 or later. Use the arcora CLI on this platform.") } }
#endif
