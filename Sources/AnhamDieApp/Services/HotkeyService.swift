import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 브리핑 토글 ⌥⌘T (PLAN §7)
    static let toggleBriefing = Self("toggleBriefing", default: .init(.t, modifiers: [.option, .command]))
    /// 오버레이 토글 ⌥⌘O
    static let toggleOverlay = Self("toggleOverlay", default: .init(.o, modifiers: [.option, .command]))
    /// 빠른 추가 ⌥⌘N
    static let quickAdd = Self("quickAdd", default: .init(.n, modifiers: [.option, .command]))
    /// 메인 창 열기/포커스 ⌥⌘M (PLAN §10.3)
    static let openMain = Self("openMain", default: .init(.m, modifiers: [.option, .command]))
}

@MainActor
enum HotkeyService {
    static func setup() {
        KeyboardShortcuts.onKeyUp(for: .toggleBriefing) {
            Task { @MainActor in BriefingController.shared.toggle() }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleOverlay) {
            Task { @MainActor in OverlayController.shared.toggle() }
        }
        KeyboardShortcuts.onKeyUp(for: .quickAdd) {
            Task { @MainActor in QuickAddController.shared.show() }
        }
        KeyboardShortcuts.onKeyUp(for: .openMain) {
            Task { @MainActor in MainWindowOpener.openMain() }
        }
    }
}
