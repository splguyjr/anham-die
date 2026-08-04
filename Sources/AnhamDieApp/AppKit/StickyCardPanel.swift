import AppKit

/// 포스트잇 카드 창 치수 (v10 §19.1).
enum StickyCardMetrics {
    /// 카드 최소 크기 — 상단 바 + 본문 몇 줄이 들어갈 하한.
    static let minSize = NSSize(width: 160, height: 140)
    /// 카드 최대 크기 — 화면을 덮지 않도록 상한.
    static let maxSize = NSSize(width: 1000, height: 1000)
    /// 상단 바 높이.
    static let barHeight: CGFloat = 26
    /// 카드 모서리 반경 — 클리어 패널이라 SwiftUI가 이 반경으로 클립하면 창 그림자도 따라 둥글어진다.
    static let cornerRadius: CGFloat = 10
}

/// 포스트잇 카드 창 (v10 §19.1). FloatingPanel(nonactivating·becomesKey) 파생 —
/// 기본은 일반 창 레벨(.normal, 다른 앱 뒤로), 핀 시에만 .floating + 모든 스페이스·전체화면 위.
/// 배경 드래그 이동은 끄고(상단 바 드래그만 이동), 가장자리 리사이즈는 켜고 하한/상한을 건다.
/// 카드 색·모서리·그림자 모양은 SwiftUI가 그리므로 패널 배경은 클리어(FloatingPanel 기본)를 유지한다.
final class StickyCardPanel: FloatingPanel {
    init(contentRect: NSRect) {
        // becomesKey: true — 본문 TextEditor 입력을 받아야 한다(비활성 패널이라 앱 활성은 뺏지 않음).
        super.init(contentRect: contentRect, becomesKey: true)
        styleMask.insert(.resizable)
        isMovableByWindowBackground = false
        contentMinSize = StickyCardMetrics.minSize
        contentMaxSize = StickyCardMetrics.maxSize
        animationBehavior = .utilityWindow
        applyPinned(false)
    }

    /// 핀 상태를 창 레벨·스페이스 동작에 반영한다 (§19.1).
    func applyPinned(_ pinned: Bool) {
        if pinned {
            level = .floating
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            level = .normal
            collectionBehavior = []
        }
    }
}
