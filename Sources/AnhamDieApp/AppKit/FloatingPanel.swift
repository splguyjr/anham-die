import AppKit

/// 비활성화 플로팅 패널 공용 베이스 (PLAN §5.2).
/// 오버레이/브리핑/빠른추가 패널이 이 클래스를 서브클래싱하거나 직접 사용한다.
/// nonactivatingPanel이라 클릭해도 현재 앱 포커스를 뺏지 않는다.
class FloatingPanel: NSPanel {
    private let acceptsKeyFocus: Bool

    /// - Parameter becomesKey: false면 키 윈도우가 되지 않는다 — 오버레이처럼 클릭해도
    ///   사용자 앱의 키보드 포커스를 뺏으면 안 되는 패널용 (PLAN §5.3).
    ///   텍스트 입력이 필요한 패널(빠른추가/브리핑)만 true.
    init(contentRect: NSRect, becomesKey: Bool = true) {
        self.acceptsKeyFocus = becomesKey
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // 싱글턴 컨트롤러가 패널을 재사용하므로 close 계열 호출 시 over-release 방지 (NSPanel 기본 true)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    override var canBecomeKey: Bool { acceptsKeyFocus }
}
