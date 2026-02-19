import AppKit
import SwiftUI

@main
struct MeetingAssistantMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .defaultSize(width: 1180, height: 780)

        MenuBarExtra {
            MenuBarQuickPanel()
                .environmentObject(store)
        } label: {
            Image(nsImage: AppIconFactory.menuBarTemplateIcon(size: 18))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIconFactory.dockIcon(size: 512)
        NSApp.activate(ignoringOtherApps: true)
    }
}
