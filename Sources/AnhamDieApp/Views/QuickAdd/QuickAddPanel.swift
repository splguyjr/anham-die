import AppKit

/// 빠른 추가용 Spotlight식 플로팅 패널 (PLAN §3.4·§7).
/// FloatingPanel(nonactivatingPanel)을 상속해 활성 앱을 완전히 활성화하지 않고도
/// 키 윈도우가 되어 텍스트 입력을 받는다. 그림자는 SwiftUI 카드가 직접 그리므로 끈다.
final class QuickAddPanel: FloatingPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 648, height: 150))
        hasShadow = false
        level = .modalPanel
        animationBehavior = .utilityWindow
    }
}
