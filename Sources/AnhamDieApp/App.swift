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
        HotkeyService.shared.setup()
        reconcileLaunchAtLogin(context.settings)
        _ = OverlayController.shared
        _ = BriefingController.shared
        _ = QuickAddController.shared
        context.triggers.start()
        context.triggers.handle(.appLaunch)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 유예 중(§11.6) 완료를 잃지 않도록 종료 전 전부 확정한다.
        CompletionGraceController.shared.flushAll()
        AppContext.shared.store.saveNow()
    }

    /// Dock 아이콘 클릭·앱 재실행(LaunchServices reopen) 시 메인 창을 표시/포커스한다 (PLAN §10.3).
    /// LSUIElement(accessory) 상태에서도 MainWindowOpener가 activate 후 창을 앞으로 올린다.
    /// 토글이 아니라 항상 열기 — ⌥⌘M 토글(§18)과 달리 Dock/reopen은 여는 의도만 갖는다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowOpener.openMain()
        return true
    }

    /// 메뉴바 상주(LSUIElement) 앱 — ⌥⌘M 토글로 마지막 창을 닫아도 앱은 살아 있어야 한다 (§18).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 시작 시 등록한 로그인 항목의 번들 경로 — BTM 등록 URL이 현재 번들과 일치하는지 판단하는 근거.
    private static let registeredLoginItemPathKey = "registeredLoginItemPath"

    /// ad-hoc 재서명/재설치 후 BTM 등록이 조용히 풀릴 수 있어 시작 시 상태를 리컨사일한다.
    /// dist/ 등 임시 경로 등록을 막기 위해 Applications 하위에서 실행 중일 때만 재등록한다.
    /// 또한 BTM에 등록된 URL이 현재(설치본) 번들과 다르면(예: 이전에 dist/ 경로가 등록된 경우)
    /// unregister 후 재등록해 재로그인 시 엉뚱한 번들이 실행되는 것을 막는다.
    private func reconcileLaunchAtLogin(_ settings: AppSettings) {
        guard settings.launchAtLogin else { return }
        guard LaunchAtLoginService.isRunningFromApplications else {
            NSLog("AnhamDie: 로그인 항목 재등록 생략 — Applications 밖 경로(\(Bundle.main.bundlePath))")
            return
        }
        let currentPath = Bundle.main.bundlePath
        let recordedPath = UserDefaults.standard.string(forKey: Self.registeredLoginItemPathKey)
        // 이미 활성 + 마지막으로 등록한 경로가 현재 번들과 같으면 손대지 않는다(불필요한 BTM 쓰기 방지).
        if LaunchAtLoginService.status == .enabled, recordedPath == currentPath { return }
        do {
            // 활성이지만 URL이 stale일 수 있으므로 먼저 해제해 오래된 경로 등록을 제거한다.
            try? LaunchAtLoginService.unregister()
            try LaunchAtLoginService.register()
            UserDefaults.standard.set(currentPath, forKey: Self.registeredLoginItemPathKey)
        } catch {
            NSLog("AnhamDie: 로그인 항목 재등록 실패 — \(error)")
        }
    }
}
