import AppKit

// 플레이스홀더 — overlay 모듈이 FloatingPanel 기반으로 구현 (PLAN §3.2)
@MainActor
final class OverlayController {
    static let shared = OverlayController()

    private(set) var isVisible = false

    func show() {
        isVisible = true
    }

    func hide() {
        isVisible = false
    }

    func toggle() {
        isVisible ? hide() : show()
    }
}
