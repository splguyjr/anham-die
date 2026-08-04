import Testing
@testable import AnhamDieApp

// PLAN §18 — ⌥⌘M 스마트 토글의 상태 판정. AppKit 상태(존재/가시/키/앱 활성)를 입력으로
// 받아 open/focus/close 3분기를 결정하는 순수 함수만 검증한다(창 조작 자체는 UI 경로).

@Suite("메인 창 토글 상태 판정 (§18)")
struct MainWindowToggleTests {
    typealias Action = MainWindowOpener.ToggleAction

    @Test("창 없음 → open")
    func noWindowOpens() {
        #expect(
            MainWindowOpener.toggleAction(
                windowExists: false, isVisible: false, isKeyWindow: false, appActive: false
            ) == .open
        )
    }

    @Test("창은 있으나 숨김 → open")
    func hiddenWindowOpens() {
        #expect(
            MainWindowOpener.toggleAction(
                windowExists: true, isVisible: false, isKeyWindow: false, appActive: true
            ) == .open
        )
    }

    @Test("보이지만 키 아님 → focus")
    func visibleNonKeyFocuses() {
        #expect(
            MainWindowOpener.toggleAction(
                windowExists: true, isVisible: true, isKeyWindow: false, appActive: true
            ) == .focus
        )
    }

    @Test("보이고 키지만 앱 비활성 → focus")
    func keyButAppInactiveFocuses() {
        #expect(
            MainWindowOpener.toggleAction(
                windowExists: true, isVisible: true, isKeyWindow: true, appActive: false
            ) == .focus
        )
    }

    @Test("보이고 키 + 앱 활성 → close")
    func keyAndActiveCloses() {
        #expect(
            MainWindowOpener.toggleAction(
                windowExists: true, isVisible: true, isKeyWindow: true, appActive: true
            ) == .close
        )
    }
}
