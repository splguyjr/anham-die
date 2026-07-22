import AppKit

/// 브리핑 전용 플로팅 패널. FloatingPanel(nonactivating/floating/allSpaces) 위에
/// Esc(cancelOperation) 닫기만 추가한다.
final class BriefingPanel: FloatingPanel {
    /// Esc 눌렀을 때 호출. BriefingController가 hide로 연결한다.
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
