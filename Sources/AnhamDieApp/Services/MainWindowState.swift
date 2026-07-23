import AppKit
import Foundation

/// 메인 창 상태 복원 스텁 (PLAN §11.7) — 저장 키는 AppSettings(mainWindowFrame/
/// mainWindowSelectedView), 여기는 변환·복원 헬퍼만 제공한다.
/// 메인 창 모듈이 연결할 지점:
/// - 창 이동/리사이즈(NSWindow didMove/didResize·windowWillClose) → saveFrame(_:)
/// - 사이드바 selection 변경 → saveSelection(_:)
/// - 창 표시 직전 → restoreFrame()으로 setFrame, restoreSelection(as:)으로 초기 selection
@MainActor
enum MainWindowState {
    /// 프레임 저장 (NSStringFromRect 포맷으로 영속)
    static func saveFrame(_ frame: CGRect, settings: AppSettings = .shared) {
        settings.mainWindowFrame = NSStringFromRect(frame)
    }

    /// 저장된 프레임. 없거나 크기가 0이면 nil (호출부는 defaultSize 유지)
    static func restoreFrame(settings: AppSettings = .shared) -> CGRect? {
        guard let stored = settings.mainWindowFrame else { return nil }
        let rect = NSRectFromString(stored)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    /// 마지막 선택 사이드바 뷰 저장 — id는 사이드바 selection의 안정적 rawValue 문자열
    static func saveSelection(_ id: String, settings: AppSettings = .shared) {
        settings.mainWindowSelectedView = id
    }

    /// 저장된 사이드바 selection을 RawRepresentable로 복원. 없거나 해석 불가면 nil
    static func restoreSelection<S: RawRepresentable>(
        as type: S.Type, settings: AppSettings = .shared
    ) -> S? where S.RawValue == String {
        settings.mainWindowSelectedView.flatMap(S.init(rawValue:))
    }

    /// 저장된 selection 원시 문자열 (커스텀 selection 타입용)
    static func restoreSelectionRawValue(settings: AppSettings = .shared) -> String? {
        settings.mainWindowSelectedView
    }
}
