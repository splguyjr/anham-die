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
        .defaultSize(width: 780, height: 560)
        // 로그인 자동실행/재시작 때 메인 창이 멋대로 뜨지 않도록 — 메뉴바 '메인 창 열기'로만 연다.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            MenuBarContentView()
        } label: {
            // 라벨 뷰는 앱 상주 내내 살아 있어 openWindow 액션 캡처 지점으로 쓴다 (⌥⌘M 등 환경 밖 열기).
            Image(systemName: "checklist")
                .background(MainWindowOpenerCapture())
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

    /// Dock 아이콘 클릭·앱 재실행(LaunchServices reopen) 시 메인 창을 표시/포커스한다 (PLAN §10.3).
    /// LSUIElement(accessory) 상태에서도 MainWindowOpener가 activate 후 창을 앞으로 올린다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowOpener.openMain()
        return true
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
