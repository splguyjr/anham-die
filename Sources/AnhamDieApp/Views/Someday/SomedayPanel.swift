import AppKit
import SwiftUI

/// '언젠가' 전용 플로팅 패널 (PLAN §22.2, ⌥⌘L). FloatingPanel(nonactivating/floating/allSpaces)에
/// Esc(cancelOperation) 닫기만 얹는다. 텍스트 입력(빠른 추가)이 필요하므로 becomesKey=true.
final class SomedayPanel: FloatingPanel {
    /// Esc 눌렀을 때 호출. SomedayPanelController가 hide로 연결한다.
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: CGSize(width: 320, height: 460)),
                   becomesKey: true)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// '언젠가' 패널의 표시/숨김·위치·크기를 관리한다 (PLAN §22.2).
/// HotkeyService.onToggleSomeday(⌥⌘L)가 toggle()로 연결된다. 드래그로 옮긴 위치·리사이즈 크기는
/// 저장/복원한다(브리핑 컨트롤러 패턴 준용). 파일 소유 경계를 지키기 위해 전용 UserDefaults 키로 자립 저장.
@MainActor
final class SomedayPanelController: NSObject, NSWindowDelegate {
    static let shared = SomedayPanelController()

    private(set) var isVisible = false
    private var panel: SomedayPanel?
    private var hosting: NSHostingView<SomedayPanelView>?
    /// 프로그램적 이동/리사이즈로 발생한 windowDidMove가 저장 위치를 덮어쓰지 않도록 하는 가드.
    private var suppressMoveSave = false

    @MainActor private let defaults = UserDefaults.standard
    private enum Keys {
        static let posX = "somedayPanelPositionX"
        static let posY = "somedayPanelPositionY"
        static let sizeW = "somedayPanelSizeWidth"
        static let sizeH = "somedayPanelSizeHeight"
    }

    // 자유 리사이즈 하한/상한·기본 크기 (브리핑 패턴 준용).
    private enum SizeMetrics {
        static let min = CGSize(width: 260, height: 260)
        static let max = CGSize(width: 560, height: 960)
        static let `default` = CGSize(width: 320, height: 460)
    }

    func show() {
        let panel = ensurePanel()
        // 재사용 패널이 '어제' 기준으로 뜨지 않도록 표시 시점 데이터로 재평가(경계 관찰과 이중 안전).
        hosting?.rootView = SomedayPanelView()
        if !isVisible { layout(panel) }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        if let panel {
            savePosition(panel)
            panel.orderOut(nil)
        }
        isVisible = false
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    private func ensurePanel() -> SomedayPanel {
        if let panel { return panel }
        let hosting = NSHostingView(rootView: SomedayPanelView())
        // 자유 리사이즈: 콘텐츠가 창 크기를 강제하지 않도록 sizingOptions를 비우고, 창 크기에 맞춰
        // 콘텐츠가 늘어나도록 autoresizing을 건다(오버레이/브리핑 패턴).
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        self.hosting = hosting
        let newPanel = SomedayPanel()
        newPanel.styleMask.insert(.resizable)
        newPanel.contentMinSize = SizeMetrics.min
        newPanel.contentMaxSize = SizeMetrics.max
        newPanel.contentView = hosting
        newPanel.delegate = self
        newPanel.onCancel = {
            MainActor.assumeIsolated { SomedayPanelController.shared.hide() }
        }
        panel = newPanel
        return newPanel
    }

    /// 저장된 크기가 있으면 복원(클램프), 없으면 기본. 저장 위치가 있으면 복원(화면 밖이면 클램프),
    /// 없으면 화면 중앙(약간 위)에 배치한다.
    private func layout(_ panel: SomedayPanel) {
        suppressMoveSave = true
        defer { suppressMoveSave = false }

        panel.setContentSize(clampSize(savedSize() ?? SizeMetrics.default))
        guard let fallbackScreen = panel.screen ?? NSScreen.main else { return }
        let size = panel.frame.size
        if let saved = savedPosition() {
            let visible = (NSScreen.screens.first { $0.frame.contains(saved) } ?? fallbackScreen).visibleFrame
            panel.setFrameOrigin(clamp(saved, size: size, into: visible))
        } else {
            let visible = fallbackScreen.visibleFrame
            let origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + min(visible.height * 0.1, 80)
            )
            panel.setFrameOrigin(origin)
        }
    }

    private func clamp(_ origin: NSPoint, size: NSSize, into visible: NSRect) -> NSPoint {
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height)
        return NSPoint(
            x: min(max(origin.x, visible.minX), maxX),
            y: min(max(origin.y, visible.minY), maxY)
        )
    }

    // MARK: - 위치/크기 저장·복원

    private func savedPosition() -> NSPoint? {
        guard defaults.object(forKey: Keys.posX) != nil,
              defaults.object(forKey: Keys.posY) != nil else { return nil }
        return NSPoint(x: defaults.double(forKey: Keys.posX), y: defaults.double(forKey: Keys.posY))
    }

    private func savePosition(_ panel: SomedayPanel) {
        let origin = panel.frame.origin
        defaults.set(Double(origin.x), forKey: Keys.posX)
        defaults.set(Double(origin.y), forKey: Keys.posY)
    }

    private func savedSize() -> CGSize? {
        guard defaults.object(forKey: Keys.sizeW) != nil,
              defaults.object(forKey: Keys.sizeH) != nil else { return nil }
        return CGSize(width: defaults.double(forKey: Keys.sizeW),
                      height: defaults.double(forKey: Keys.sizeH))
    }

    private func saveSize(_ panel: SomedayPanel) {
        let size = panel.contentRect(forFrameRect: panel.frame).size
        defaults.set(Double(size.width), forKey: Keys.sizeW)
        defaults.set(Double(size.height), forKey: Keys.sizeH)
    }

    private func clampSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, SizeMetrics.min.width), SizeMetrics.max.width),
            height: min(max(size.height, SizeMetrics.min.height), SizeMetrics.max.height)
        )
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard !suppressMoveSave, let panel else { return }
        savePosition(panel)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        suppressMoveSave = true
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        suppressMoveSave = false
        guard let panel else { return }
        saveSize(panel)
        savePosition(panel)
    }
}
