import AppKit

/// 비활성화 플로팅 패널 공용 베이스 (PLAN §5.2).
/// 오버레이/브리핑/빠른추가 패널이 이 클래스를 서브클래싱하거나 직접 사용한다.
/// nonactivatingPanel이라 클릭해도 현재 앱 포커스를 뺏지 않는다.
class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
}
