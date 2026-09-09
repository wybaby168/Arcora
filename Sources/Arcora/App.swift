#if os(macOS)
import SwiftUI
import AppKit
import ArcoraCore

@main
struct ArcoraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model:AppModel {delegate.model}
    var body: some Scene {
        // The archive, jobs and sheet state belong to one application-wide
        // model. A WindowGroup lets file-open events create extra sheet hosts.
        Window("Arcora",id:"main") {
            ArchiveRootView(model:model)
        }
        .defaultSize(width:1080,height:730)
        .windowStyle(.titleBar)
        .commands { ArchiveCommands(model:model) }
        Settings { ArchiveSettingsRoot(model:model) }
    }
}
private struct ArchiveRootView:View {
    @ObservedObject var model:AppModel
    var body:some View {
        MainWindow(model:model)
            .environment(\.locale,model.locale)
            .preferredColorScheme(model.preferences.appearance == "dark" ? .dark : model.preferences.appearance == "light" ? .light : nil)
    }
}
private struct ArchiveSettingsRoot:View {
    @ObservedObject var model:AppModel
    var body:some View {SettingsView(model:model).environment(\.locale,model.locale)}
}
private struct ArchiveCommands:Commands {
    @ObservedObject var model:AppModel
    var body:some Commands {
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
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Services can launch the app before any SwiftUI window appears.
    // The delegate owns the model for the whole application lifetime.
    let model=AppModel()
    private let finderServices=FinderServicesProvider()
    func applicationDidFinishLaunching(_ notification:Notification) {
        finderServices.handler = { [weak self] request in
            guard let self else {return}
            self.model.reopenMainWindow?()
            NSApp.activate(ignoringOtherApps:true)
            self.model.receiveFinderRequest(request)
        }
        NSApp.servicesProvider=finderServices
        NSUpdateDynamicServices()
    }
    func application(_ application:NSApplication,open urls:[URL]) {
        // Route Finder/Open With events once, outside the view hierarchy.
        // On a cold launch SwiftUI creates the primary Window; after closing
        // it the retained openWindow action restores that same unique scene.
        model.reopenMainWindow?()
        application.activate(ignoringOtherApps:true)
        for url in urls where url.isFileURL {model.open(url)}
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {
        model.reopenMainWindow?()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {
        // Keep queued/running jobs alive, matching the previous WindowGroup.
        false
    }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
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
}
#else
import Foundation
@main struct UnsupportedPlatform { static func main() { print("Arcora's graphical interface requires macOS 14 or later. Use the arcora CLI on this platform.") } }
#endif
