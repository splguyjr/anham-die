import AppKit
import SwiftUI

@main
struct AnhamDieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("AnhamDie", id: "main") {
            MainWindowView()
        }
        .defaultSize(width: 420, height: 560)

        MenuBarExtra {
            MenuBarContentView()
        } label: {
            Image(systemName: "checklist")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let context = AppContext.shared
        NSApp.setActivationPolicy(context.settings.showDockIcon ? .regular : .accessory)
        HotkeyService.setup()
        _ = OverlayController.shared
        _ = BriefingController.shared
        _ = QuickAddController.shared
        context.triggers.start()
        context.triggers.handle(.appLaunch)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppContext.shared.store.saveNow()
    }
}
