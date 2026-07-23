import Foundation
import Testing
@testable import AnhamDieApp

// PLAN §11.4 — 예외 앱 판정과 단축키 설정 저장 구조. §11.7 — 메인 창 상태 헬퍼.

@Suite("단축키 예외 앱 판정")
struct HotkeyExemptionTests {
    @Test("접두사 일치 (기본값 JetBrains 계열)")
    func prefixMatch() {
        let prefixes = AppSettings.defaultHotkeyExceptionAppPrefixes
        #expect(HotkeyService.isExempt(bundleID: "com.jetbrains.intellij", prefixes: prefixes))
        #expect(HotkeyService.isExempt(bundleID: "com.jetbrains.pycharm.ce", prefixes: prefixes))
        #expect(!HotkeyService.isExempt(bundleID: "com.apple.Safari", prefixes: prefixes))
    }

    @Test("대소문자 무시·정확한 번들ID도 접두사로 동작")
    func caseInsensitiveAndExact() {
        #expect(HotkeyService.isExempt(bundleID: "com.JetBrains.IntelliJ", prefixes: ["com.jetbrains."]))
        #expect(HotkeyService.isExempt(bundleID: "com.googlecode.iterm2", prefixes: ["com.googlecode.iterm2"]))
    }

    @Test("nil 번들ID·빈 접두사는 예외 아님")
    func nilAndEmpty() {
        #expect(!HotkeyService.isExempt(bundleID: nil, prefixes: ["com.jetbrains."]))
        #expect(!HotkeyService.isExempt(bundleID: "com.example.app", prefixes: ["", "  "]))
    }
}

@Suite("단축키·메인 창 설정 저장 구조")
struct HotkeySettingsPersistenceTests {
    func makeSuite() -> (UserDefaults, String) {
        let name = "AnhamDieTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    @Test("기본값: 마스터 on, 개별 전부 on, 예외 = JetBrains")
    func defaults() {
        let (defaults, _) = makeSuite()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.hotkeysMasterEnabled)
        #expect(settings.disabledHotkeyIDs.isEmpty)
        #expect(settings.hotkeyExceptionAppPrefixes == ["com.jetbrains."])
        #expect(settings.mainWindowFrame == nil)
        #expect(settings.mainWindowSelectedView == nil)
    }

    @Test("저장·재로드 왕복")
    func roundtrip() {
        let (defaults, _) = makeSuite()
        let settings = AppSettings(defaults: defaults)
        settings.hotkeysMasterEnabled = false
        settings.disabledHotkeyIDs = ["quickAdd", "openMain"]
        settings.hotkeyExceptionAppPrefixes = ["com.jetbrains.", "com.microsoft.VSCode"]
        settings.mainWindowSelectedView = "backlog"

        let reloaded = AppSettings(defaults: defaults)
        #expect(!reloaded.hotkeysMasterEnabled)
        #expect(reloaded.disabledHotkeyIDs == ["quickAdd", "openMain"])
        #expect(reloaded.hotkeyExceptionAppPrefixes == ["com.jetbrains.", "com.microsoft.VSCode"])
        #expect(reloaded.mainWindowSelectedView == "backlog")
    }

    @Test("설정 변경 시 hotkeySettingsDidChange 게시")
    func postsChangeNotification() {
        let (defaults, _) = makeSuite()
        let settings = AppSettings(defaults: defaults)
        var count = 0
        let observer = NotificationCenter.default.addObserver(
            forName: AppSettings.hotkeySettingsDidChange, object: settings, queue: nil
        ) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        settings.hotkeysMasterEnabled = false
        settings.disabledHotkeyIDs = ["quickAdd"]
        settings.hotkeyExceptionAppPrefixes = []
        #expect(count == 3)
    }

    @MainActor
    @Test("메인 창 프레임 저장·복원 헬퍼 (§11.7)")
    func mainWindowFrameRoundtrip() {
        let (defaults, _) = makeSuite()
        let settings = AppSettings(defaults: defaults)
        #expect(MainWindowState.restoreFrame(settings: settings) == nil)

        let frame = CGRect(x: 120, y: 240, width: 780, height: 560)
        MainWindowState.saveFrame(frame, settings: settings)
        #expect(MainWindowState.restoreFrame(settings: settings) == frame)

        enum SidebarStub: String { case today, backlog }
        MainWindowState.saveSelection(SidebarStub.backlog.rawValue, settings: settings)
        #expect(MainWindowState.restoreSelection(as: SidebarStub.self, settings: settings) == .backlog)
    }
}
