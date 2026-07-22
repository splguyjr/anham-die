import AppKit
import SwiftUI

/// 컴팩트 플로팅 오버레이 컨트롤러 (PLAN §3.2).
/// FloatingPanel(nonactivating, .floating, canJoinAllSpaces+fullScreenAuxiliary) 위에
/// SwiftUI 카드를 올리고, 위치·표시상태를 AppSettings에 저장/복원한다.
@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    static let shared = OverlayController()

    private let settings = AppContext.shared.settings
    private let store = AppContext.shared.store
    private let boundary = AppContext.shared.dayBoundary

    private var panel: FloatingPanel?
    // 프로그램적 이동/리사이즈로 발생한 windowDidMove가 저장 위치를 덮어쓰지 않도록 하는 가드.
    private var suppressMoveSave = false
    // show() 직후 첫 실측(onResize)에서 저장된 좌하단 origin으로 재배치하기 위한 플래그.
    // 추정 높이와 실측 높이의 차이가 좌상단 고정 리사이즈를 거치며 origin을 밀어 올리고,
    // hide()가 그 값을 다시 저장해 토글마다 드리프트가 누적되는 것을 막는다 (§10.4).
    private var pendingPositionRestore = false

    var isVisible: Bool { panel?.isVisible ?? false }

    private override init() {
        super.init()
        // 이전 세션에서 표시 중이었으면 복원한다.
        if settings.overlayVisible {
            show()
        }
    }

    func show() {
        let panel = ensurePanel()
        suppressMoveSave = true
        panel.setContentSize(estimatedSize())
        suppressMoveSave = false
        pendingPositionRestore = true
        positionPanel(panel)
        panel.orderFrontRegardless()
        settings.overlayVisible = true
    }

    func hide() {
        if let panel {
            settings.overlayPosition = panel.frame.origin
            panel.orderOut(nil)
        }
        settings.overlayVisible = false
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    // MARK: - 패널 구성

    private func ensurePanel() -> FloatingPanel {
        if let panel { return panel }
        // becomesKey: false — 체크박스 클릭이 사용자 앱의 키보드 포커스를 뺏으면 안 된다 (PLAN §5.3)
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: estimatedSize()), becomesKey: false)
        let root = OverlayRootView(onResize: { [weak self] size in
            self?.resizePanel(to: size)
        })
        let hosting = OverlayHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.delegate = self
        self.panel = panel
        return panel
    }

    /// 콘텐츠 높이를 측정값에 맞추되, 좌상단을 고정해 아래로 자라게 한다.
    /// 단, show() 후 첫 실측이면 저장된 좌하단 origin 기준으로 재배치한다 —
    /// 추정 오차가 저장 위치를 드리프트시키지 않도록.
    private func resizePanel(to size: CGSize) {
        guard let panel else { return }
        if pendingPositionRestore {
            pendingPositionRestore = false
            suppressMoveSave = true
            panel.setContentSize(size)
            suppressMoveSave = false
            positionPanel(panel)
            return
        }
        let current = panel.frame
        let newHeight = size.height
        let topLeftY = current.origin.y + current.height
        let newFrame = NSRect(
            x: current.origin.x,
            y: topLeftY - newHeight,
            width: size.width,
            height: newHeight
        )
        guard newFrame != current else { return }
        suppressMoveSave = true
        panel.setFrame(newFrame, display: true)
        suppressMoveSave = false
    }

    private func positionPanel(_ panel: FloatingPanel) {
        let size = panel.frame.size
        let origin: NSPoint
        if let saved = settings.overlayPosition {
            let screen = NSScreen.screens.first { $0.frame.contains(saved) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            origin = clamp(saved, size: size, into: visible)
        } else if let visible = NSScreen.main?.visibleFrame {
            let margin: CGFloat = 24
            origin = NSPoint(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin)
        } else {
            origin = NSPoint(x: 100, y: 100)
        }
        suppressMoveSave = true
        panel.setFrameOrigin(origin)
        suppressMoveSave = false
    }

    private func clamp(_ origin: NSPoint, size: NSSize, into visible: NSRect) -> NSPoint {
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height)
        return NSPoint(
            x: min(max(origin.x, visible.minX), maxX),
            y: min(max(origin.y, visible.minY), maxY)
        )
    }

    /// 콘텐츠 렌더 전 첫 표시의 깜빡임을 줄이기 위한 대략적 높이. 실제 높이는 onResize가 보정한다.
    private func estimatedSize() -> CGSize {
        let base = store.todayTasks(boundary: boundary)
        let maxCount = max(1, settings.overlayMaxCount)
        let rows = base.isEmpty ? 1 : min(base.count, maxCount)
        let hasMore = base.count > maxCount
        let hasRollover = base.contains { $0.rolloverCount > 0 }

        var height = OverlayMetrics.vPadding * 2
        height += OverlayMetrics.headerHeight
        height += OverlayMetrics.dividerHeight
        height += CGFloat(rows) * OverlayMetrics.rowHeight
        if hasMore { height += OverlayMetrics.moreHeight }
        if hasRollover { height += OverlayMetrics.footerHeight }
        // VStack spacing은 요소 '사이'에만 붙는다: (요소 수 - 1)개.
        let elements = 2 + rows + (hasMore ? 1 : 0) + (hasRollover ? 1 : 0)
        height += CGFloat(elements - 1) * OverlayMetrics.rowSpacing
        return CGSize(width: OverlayMetrics.width, height: height)
    }

    // MARK: - NSWindowDelegate

    // 사용자가 드래그로 옮겼을 때만 위치를 저장한다 (프로그램적 이동은 가드로 무시).
    func windowDidMove(_ notification: Notification) {
        guard !suppressMoveSave, let panel else { return }
        settings.overlayPosition = panel.frame.origin
    }
}
