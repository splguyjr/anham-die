import AppKit

// 플레이스홀더 — quickadd 모듈이 Spotlight식 입력창으로 구현 (PLAN §7)
@MainActor
final class QuickAddController {
    static let shared = QuickAddController()

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
