import AppKit
import ServiceManagement
import SwiftUI

@main
struct AnhamDieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("AnhamDie", id: "main") {
            MainWindowView()
        }
        .defaultSize(width: 420, height: 560)
        // 로그인 자동실행/재시작 때 메인 창이 멋대로 뜨지 않도록 — 메뉴바 '메인 창 열기'로만 연다.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

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
        // KeyboardShortcuts.Name 최초 참조는 didFinishLaunching 이후여야 핸들러가 설치된다
        // (이전 시점 참조는 Carbon 등록만 되고 핸들러 없는 좀비 핫키가 됨) — 이 위치 유지.
        HotkeyService.setup()
        reconcileLaunchAtLogin(context.settings)
        _ = OverlayController.shared
        _ = BriefingController.shared
        _ = QuickAddController.shared
        context.triggers.start()
        context.triggers.handle(.appLaunch)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppContext.shared.store.saveNow()
    }

    /// ad-hoc 재서명/재설치 후 BTM 등록이 조용히 풀릴 수 있어 시작 시 상태를 리컨사일한다.
    /// dist/ 등 임시 경로 등록을 막기 위해 Applications 하위에서 실행 중일 때만 재등록한다.
    private func reconcileLaunchAtLogin(_ settings: AppSettings) {
        guard settings.launchAtLogin else { return }
        guard LaunchAtLoginService.status != .enabled else { return }
        guard LaunchAtLoginService.isRunningFromApplications else {
            NSLog("AnhamDie: 로그인 항목 재등록 생략 — Applications 밖 경로(\(Bundle.main.bundlePath))")
            return
        }
        do {
            try LaunchAtLoginService.register()
        } catch {
            NSLog("AnhamDie: 로그인 항목 재등록 실패 — \(error)")
        }
    }
}
