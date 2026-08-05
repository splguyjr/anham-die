import AppKit
import SwiftUI

/// 브리핑 패널(플로팅 창)의 표시/숨김·위치를 관리한다 (PLAN §2·§10.4).
/// TriggerService.onBriefingRequested를 여기서 연결해 자동 트리거(시작/웨이크/시각 도달)에
/// 반응하고, 단축키/메뉴바 호출 시엔 toggle()로 판단 없이 즉시 전환한다.
/// 드래그로 옮긴 위치는 저장/복원한다(오버레이 위치 저장 패턴 준용). 파일 소유 경계를 지키기 위해
/// AppSettings 대신 전용 UserDefaults 키로 자립 저장한다.
@MainActor
final class BriefingController: NSObject, NSWindowDelegate {
    static let shared = BriefingController()

    private(set) var isVisible = false
    private var panel: BriefingPanel?
    private var hosting: NSHostingView<BriefingView>?
    // 프로그램적 이동/리사이즈로 발생한 windowDidMove가 저장 위치를 덮어쓰지 않도록 하는 가드.
    private var suppressMoveSave = false

    @MainActor private let defaults = UserDefaults.standard
    private enum Keys {
        static let posX = "briefingPositionX"
        static let posY = "briefingPositionY"
        static let sizeW = "briefingSizeWidth"
        static let sizeH = "briefingSizeHeight"
    }

    // 자유 리사이즈 하한/상한·기본 크기 (§21.3, 오버레이 패턴 준용).
    private enum SizeMetrics {
        static let min = CGSize(width: 320, height: 320)
        static let max = CGSize(width: 640, height: 960)
        static let `default` = CGSize(width: 380, height: 480)
    }

    private override init() {
        super.init()
        // 자동 트리거는 TriggerService.handle()이 노출 판단을 마친 뒤에만 호출한다.
        AppContext.shared.triggers.onBriefingRequested = { _ in
            MainActor.assumeIsolated {
                BriefingController.shared.show()
            }
        }
    }

    func show() {
        let panel = ensurePanel()
        // 2일차부터 재사용되는 패널이 '어제' 기준 캐시로 뜨지 않도록, 표시 시점 데이터로 강제 재평가.
        // (경계 통과는 AppSettings.currentLogicalDay 관찰로도 갱신되지만 표시 직전에 한 번 더 보장한다.)
        hosting?.rootView = BriefingView()
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
        if let panel {
            savePosition(panel)
            panel.orderOut(nil)
        }
        isVisible = false
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    private func ensurePanel() -> BriefingPanel {
        if let panel { return panel }
        let hosting = NSHostingView(rootView: BriefingView())
        // 자유 리사이즈(§21.3): 콘텐츠가 창 크기를 강제하지 않도록 sizingOptions를 비우고,
        // 창 크기에 맞춰 콘텐츠가 늘어나도록 autoresizing을 건다(오버레이 패턴).
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        self.hosting = hosting
        let newPanel = BriefingPanel(contentRect: NSRect(origin: .zero, size: SizeMetrics.default))
        // borderless nonactivating 패널을 가장자리 드래그로 리사이즈 가능하게 하고 하한/상한을 건다.
        newPanel.styleMask.insert(.resizable)
        newPanel.contentMinSize = SizeMetrics.min
        newPanel.contentMaxSize = SizeMetrics.max
        newPanel.contentView = hosting
        newPanel.delegate = self
        newPanel.onCancel = {
            MainActor.assumeIsolated { BriefingController.shared.hide() }
        }
        panel = newPanel
        return newPanel
    }

    /// 콘텐츠 크기에 맞춰 패널을 재조정하고, 저장된 위치가 있으면 복원(화면 밖이면 클램프),
    /// 없으면 화면 중앙(약간 위)에 배치한다.
    private func layout(_ panel: BriefingPanel) {
        // 크기·위치 변경으로 발생하는 windowDidMove가 저장 위치를 덮어쓰지 않도록 가드.
        suppressMoveSave = true
        defer { suppressMoveSave = false }

        // 저장된 크기가 있으면 복원(클램프), 없으면 콘텐츠 맞춤(없으면 기본). 이후 사용자가 리사이즈해
        // 저장하면 그 크기를 유지한다 (§21.3, 오버레이 크기 저장 패턴).
        if let saved = savedSize() {
            panel.setContentSize(clampSize(saved))
        } else if let content = panel.contentView {
            content.layoutSubtreeIfNeeded()
            let fitting = content.fittingSize
            let base = (fitting.width > 0 && fitting.height > 0) ? fitting : SizeMetrics.default
            panel.setContentSize(clampSize(base))
        } else {
            panel.setContentSize(SizeMetrics.default)
        }
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

    // MARK: - 위치 저장/복원

    private func savedPosition() -> NSPoint? {
        guard defaults.object(forKey: Keys.posX) != nil,
              defaults.object(forKey: Keys.posY) != nil else { return nil }
        return NSPoint(x: defaults.double(forKey: Keys.posX), y: defaults.double(forKey: Keys.posY))
    }

    private func savePosition(_ panel: BriefingPanel) {
        let origin = panel.frame.origin
        defaults.set(Double(origin.x), forKey: Keys.posX)
        defaults.set(Double(origin.y), forKey: Keys.posY)
    }

    // MARK: - 크기 저장/복원 (§21.3)

    private func savedSize() -> CGSize? {
        guard defaults.object(forKey: Keys.sizeW) != nil,
              defaults.object(forKey: Keys.sizeH) != nil else { return nil }
        return CGSize(width: defaults.double(forKey: Keys.sizeW),
                      height: defaults.double(forKey: Keys.sizeH))
    }

    private func saveSize(_ panel: BriefingPanel) {
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

    // 사용자가 드래그로 옮겼을 때만 위치를 저장한다 (프로그램적 이동은 가드로 무시).
    func windowDidMove(_ notification: Notification) {
        guard !suppressMoveSave, let panel else { return }
        savePosition(panel)
    }

    // 가장자리 리사이즈 시작 — 라이브 리사이즈 중 windowDidMove의 반복 저장을 억제하고,
    // 종료 시(windowDidEndLiveResize) 크기·위치를 1회만 저장한다(에너지).
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
