import AppKit
import SwiftUI

/// 컴팩트 플로팅 오버레이 컨트롤러 (PLAN §3.2 + §11.2).
/// FloatingPanel(nonactivating, .floating, canJoinAllSpaces+fullScreenAuxiliary) 위에
/// SwiftUI 카드를 올린다. v3: 패널을 자유 리사이즈 가능하게 하고(styleMask .resizable, min/max),
/// 위치·크기·표시상태를 저장/복원한다. 창 이동은 헤더 드래그로만(isMovableByWindowBackground 해제).
@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    static let shared = OverlayController()

    private let settings = AppContext.shared.settings
    private let store = AppContext.shared.store
    private let boundary = AppContext.shared.dayBoundary

    // 크기 저장 키 — 위치(overlayPosition)와 달리 AppSettings에 없어 UserDefaults에 직접 둔다.
    private enum SizeKeys {
        static let width = "overlaySizeWidth"
        static let height = "overlaySizeHeight"
    }

    private var panel: FloatingPanel?
    // 프로그램적 이동/리사이즈로 발생한 windowDidMove가 저장 위치를 덮어쓰지 않도록 하는 가드.
    private var suppressMoveSave = false

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
        panel.setContentSize(restoredOrDefaultSize())
        suppressMoveSave = false
        positionPanel(panel)
        panel.orderFrontRegardless()
        settings.overlayVisible = true
    }

    func hide() {
        if let panel {
            settings.overlayPosition = panel.frame.origin
            saveSize(contentSize(of: panel))
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
        // becomesKey: false — 체크 원 클릭이 사용자 앱의 키보드 포커스를 뺏으면 안 된다 (PLAN §5.3)
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: defaultSize()),
            becomesKey: false
        )
        // 자유 리사이즈 (§11.2): borderless nonactivating 패널을 가장자리 드래그로 리사이즈 가능하게 하고
        // 하한/상한을 건다. 배경 드래그 이동은 끄고(헤더 드래그만 이동), origin/size는 델리게이트가 저장한다.
        panel.styleMask.insert(.resizable)
        panel.isMovableByWindowBackground = false
        panel.contentMinSize = OverlayMetrics.minContentSize
        panel.contentMaxSize = OverlayMetrics.maxContentSize

        let hosting = OverlayHostingView(rootView: OverlayRootView())
        hosting.autoresizingMask = [.width, .height]
        // 콘텐츠가 창 크기를 강제하지 않도록(자유 리사이즈 방해 방지) 크기 옵션을 비운다.
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.delegate = self
        self.panel = panel
        return panel
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

    // MARK: - 크기 저장/복원

    private func contentSize(of panel: FloatingPanel) -> CGSize {
        panel.contentRect(forFrameRect: panel.frame).size
    }

    private func saveSize(_ size: CGSize) {
        UserDefaults.standard.set(Double(size.width), forKey: SizeKeys.width)
        UserDefaults.standard.set(Double(size.height), forKey: SizeKeys.height)
    }

    private func restoredOrDefaultSize() -> CGSize {
        let d = UserDefaults.standard
        guard let w = d.object(forKey: SizeKeys.width) as? Double,
              let h = d.object(forKey: SizeKeys.height) as? Double else {
            return defaultSize()
        }
        return clampToLimits(CGSize(width: w, height: h))
    }

    private func clampToLimits(_ size: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, OverlayMetrics.minContentSize.width), OverlayMetrics.maxContentSize.width),
            height: min(max(size.height, OverlayMetrics.minContentSize.height), OverlayMetrics.maxContentSize.height)
        )
    }

    /// 저장된 크기가 없을 때의 기본 크기 — 대략 오늘 개수(최대 overlayMaxCount)만큼의 높이.
    private func defaultSize() -> CGSize {
        let count = store.todayTasks(boundary: boundary).count
        let rows = max(1, min(count, max(1, settings.overlayMaxCount)))
        var height = OverlayMetrics.vPadding * 2
        height += OverlayMetrics.headerHeight
        height += OverlayMetrics.dividerHeight
        height += CGFloat(rows) * (OverlayMetrics.rowHeight + OverlayMetrics.rowSpacing)
        return clampToLimits(CGSize(width: OverlayMetrics.defaultWidth, height: height))
    }

    // MARK: - NSWindowDelegate

    // 사용자가 헤더 드래그로 옮겼을 때만 위치를 저장한다 (프로그램적 이동은 가드로 무시).
    func windowDidMove(_ notification: Notification) {
        guard !suppressMoveSave, let panel else { return }
        settings.overlayPosition = panel.frame.origin
    }

    // 사용자 리사이즈 종료 시 크기·위치를 저장한다 (가장자리 드래그는 origin도 바꿀 수 있다).
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel else { return }
        saveSize(contentSize(of: panel))
        settings.overlayPosition = panel.frame.origin
    }
}
