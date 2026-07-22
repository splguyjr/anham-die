import AppKit

// 플레이스홀더 — briefing 모듈이 구현 (PLAN §2).
// 완성 시 AppContext.shared.triggers.onBriefingRequested를 여기서 연결하고,
// TriggerService.start()의 웨이크/시각 트리거 구독도 채운다.
@MainActor
final class BriefingController {
    static let shared = BriefingController()

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
