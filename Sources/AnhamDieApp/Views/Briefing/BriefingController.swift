import AppKit
import SwiftUI

/// 브리핑 패널(플로팅 창)의 표시/숨김을 관리한다 (PLAN §2).
/// TriggerService.onBriefingRequested를 여기서 연결해 자동 트리거(시작/웨이크/시각 도달)에
/// 반응하고, 단축키/메뉴바 호출 시엔 toggle()로 판단 없이 즉시 전환한다.
@MainActor
final class BriefingController {
    static let shared = BriefingController()

    private(set) var isVisible = false
    private var panel: BriefingPanel?

    private init() {
        // 자동 트리거는 TriggerService.handle()이 노출 판단을 마친 뒤에만 호출한다.
        AppContext.shared.triggers.onBriefingRequested = { _ in
            MainActor.assumeIsolated {
                BriefingController.shared.show()
            }
        }
    }

    func show() {
        let panel = ensurePanel()
        layout(panel)
        panel.makeKeyAndOrderFront(nil)
        // 같은 .floating 레벨의 오버레이보다 확실히 앞에 오도록
        panel.orderFrontRegardless()
        isVisible = true
        // "봤음" 기록은 실제 표시가 확정된 이 시점에서만 — 콜백 미연결/잠금 화면 등으로
        // 못 본 채 그날 자동 브리핑이 소진되는 것을 막는다 (TriggerService 참조).
        AppContext.shared.triggers.markBriefingShown()
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    private func ensurePanel() -> BriefingPanel {
        if let panel { return panel }
        let hosting = NSHostingView(rootView: BriefingView())
        hosting.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
        let newPanel = BriefingPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 420))
        newPanel.contentView = hosting
        newPanel.onCancel = {
            MainActor.assumeIsolated { BriefingController.shared.hide() }
        }
        panel = newPanel
        return newPanel
    }

    /// 콘텐츠 크기에 맞춰 패널을 재조정하고 화면 중앙(약간 위)에 배치한다.
    private func layout(_ panel: BriefingPanel) {
        if let content = panel.contentView {
            content.layoutSubtreeIfNeeded()
            let fitting = content.fittingSize
            if fitting.width > 0, fitting.height > 0 {
                panel.setContentSize(fitting)
            }
        }
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + min(visible.height * 0.1, 80)
        )
        panel.setFrameOrigin(origin)
    }
}
