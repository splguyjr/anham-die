import AppKit
import SwiftUI

/// 메인 창 열기/포커스의 단일 경로 (PLAN §10.3).
/// 호출처: ⌥⌘M 핫키 · Dock 재클릭(applicationShouldHandleReopen) · 오버레이 헤더 클릭 · 메뉴바 팝오버.
/// SwiftUI Window("main") 씬은 환경 밖에서 직접 열 수 없어, 앱 시작 시 살아 있는 뷰
/// (MenuBarExtra 라벨)에서 openWindow 액션을 캡처해 둔다 (MainWindowOpenerCapture).
@MainActor
enum MainWindowOpener {
    static let mainWindowID = "main"

    private static var openAction: (() -> Void)?

    /// openWindow(id: "main")을 감싼 클로저 등록. MainWindowOpenerCapture가 호출한다.
    static func registerOpenAction(_ action: @escaping () -> Void) {
        openAction = action
    }

    /// 메인 창을 열고 전면·키 포커스로 가져온다. 이미 열려 있으면 포커스만.
    static func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = existingMainWindow() {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            openAction?()
            bringToFront(retriesLeft: 10)
        }
    }

    /// ⌥⌘M 스마트 토글 (PLAN §18): 없음/숨김 → 열기, 보이지만 뒤 → 앞으로, 키+활성 → 닫기.
    /// 브리핑(⌥⌘T)·오버레이(⌥⌘O) 토글과 같은 멘탈 모델. Dock·메뉴바 열기는 openMain 유지.
    static func toggle() {
        let window = existingMainWindow()
        let action = toggleAction(
            windowExists: window != nil,
            isVisible: window?.isVisible ?? false,
            isKeyWindow: window?.isKeyWindow ?? false,
            appActive: NSApp.isActive
        )
        switch action {
        case .open:
            openMain()
        case .focus:
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
        case .close:
            // close()가 willCloseNotification을 발화해 MainWindowConfigurator의 프레임 저장이
            // 닫기 전에 반영된다(§11.7 저장 경로 유지). windowShouldClose를 막는 델리게이트 없음.
            window?.close()
        }
    }

    private static func existingMainWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == mainWindowID }
    }

    /// ⌥⌘M 토글이 취할 동작 (PLAN §18). AppKit 상태를 입력으로 받는 순수 함수 — 유닛 테스트 대상.
    enum ToggleAction: Equatable {
        case open   // 창 없음/숨김 → 기존 열기 경로
        case focus  // 보이지만 키 아님(또는 앱 비활성) → 앞으로 가져와 활성화
        case close  // 보이고 키 윈도우 + 앱 활성 → 닫기
    }

    /// 없음/숨김→open, 뒤에 있음→focus, 맨 앞·활성→close 3분기.
    nonisolated static func toggleAction(
        windowExists: Bool, isVisible: Bool, isKeyWindow: Bool, appActive: Bool
    ) -> ToggleAction {
        guard windowExists, isVisible else { return .open }
        return (isKeyWindow && appActive) ? .close : .focus
    }

    /// openWindow 직후엔 창이 아직 NSApp.windows에 없을 수 있어 짧게 재시도한다.
    private static func bringToFront(retriesLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let window = existingMainWindow() {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            } else if retriesLeft > 0 {
                bringToFront(retriesLeft: retriesLeft - 1)
            }
        }
    }
}

/// 항상 살아 있는 뷰 계층(MenuBarExtra 라벨)에 배경으로 붙여 openWindow 액션을 캡처한다.
struct MainWindowOpenerCapture: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                MainWindowOpener.registerOpenAction {
                    openWindow(id: MainWindowOpener.mainWindowID)
                }
            }
    }
}
