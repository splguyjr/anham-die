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

    private static func existingMainWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == mainWindowID }
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
