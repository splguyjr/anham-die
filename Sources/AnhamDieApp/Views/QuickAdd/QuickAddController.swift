import AppKit
import SwiftUI

/// 빠른 추가(⌥⌘N) 컨트롤러 — 어디서든 Spotlight식 입력창을 띄운다 (PLAN §3.4·§7).
/// nonactivating 패널이라 현재 앱 포커스를 뺏지 않으면서도 키 윈도우가 되어 입력을 받는다.
@MainActor
final class QuickAddController {
    static let shared = QuickAddController()

    private(set) var isVisible = false
    private var panel: QuickAddPanel?
    private var escMonitor: Any?

    func show() {
        let panel = ensurePanel()
        installContent(in: panel)
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installEscMonitor()
        isVisible = true
    }

    func hide() {
        removeEscMonitor()
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    // MARK: - 태스크 추가

    /// 입력 확정 처리. 제목이 있으면 오늘(논리적 하루)에 태스크를 추가한다.
    /// keepOpen이면 창을 유지(연속 입력), 아니면 닫는다.
    private func commit(_ raw: String, keepOpen: Bool) {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            let context = AppContext.shared
            // scheduledDate 저장 규약: 항상 DayBoundaryService.scheduledToday() (startOfLogicalDay)
            let task = TodoTask(title: title, scheduledDate: context.dayBoundary.scheduledToday())
            context.store.addTask(task)
        }
        if !keepOpen {
            hide()
        }
    }

    // MARK: - 패널 구성

    private func ensurePanel() -> QuickAddPanel {
        if let panel { return panel }
        let panel = QuickAddPanel()
        self.panel = panel
        return panel
    }

    private func installContent(in panel: QuickAddPanel) {
        let view = QuickAddView(
            onCommit: { [weak self] text, keepOpen in
                self?.commit(text, keepOpen: keepOpen)
            },
            onCancel: { [weak self] in
                self?.hide()
            }
        )
        let hosting = NSHostingView(rootView: view)
        var size = hosting.fittingSize
        if size.width < 1 || size.height < 1 {
            size = NSSize(width: 648, height: 150)
        }
        hosting.setFrameSize(size)
        panel.setContentSize(size)
        panel.contentView = hosting
    }

    private func position(_ panel: QuickAddPanel) {
        let screen = currentScreen()
        let size = panel.frame.size
        let x = screen.frame.midX - size.width / 2
        // Spotlight처럼 화면 상단 약 62% 높이에 중앙 정렬
        let y = screen.frame.minY + screen.frame.height * 0.62 - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func currentScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
            ?? NSScreen()
    }

    // MARK: - Esc 처리

    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event } // 53 = Esc
            MainActor.assumeIsolated { self?.hide() }
            return nil
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }
}
