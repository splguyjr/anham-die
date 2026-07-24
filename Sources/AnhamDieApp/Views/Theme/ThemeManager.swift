import Observation
import SwiftUI

/// v5 동적 테마 (PLAN §13.2) — 현재 팔레트 + 사용자 강조색 오버라이드를 결합해
/// 앱 전역에 실시간 색을 공급한다. AppSettings에 선택 팔레트·강조색을 영속하고,
/// AppTheme.* 색 참조가 전부 이 매니저(전역 shared)를 경유한다.
///
/// 반응성: 색 접근이 `settings.selectedThemeID`/`settings.accentColorHex`(둘 다 @Observable
/// 저장 프로퍼티) 읽기로 귀결되므로, SwiftUI body에서 AppTheme.* 를 읽는 것만으로 관찰이
/// 등록된다 → 설정 변경 시 전 화면이 재평가된다(추가 배선 불필요).
@Observable
final class ThemeManager {
    /// AppTheme.* 정적 색이 참조하는 전역 인스턴스. AppContext.theme와 동일 객체.
    static let shared = ThemeManager(settings: .shared)

    @ObservationIgnored let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 현재 선택된 프리셋 팔레트(미상 id는 기본으로 폴백).
    var palette: ThemePalette {
        ThemePalette.preset(for: settings.selectedThemeID)
    }

    /// 최종 강조색 — 사용자 오버라이드(#RRGGBB)가 있으면 그것, 없거나 파싱 실패면 팔레트 기본.
    var accent: Color {
        if let hex = settings.accentColorHex, let color = ColorHex.color(hex) {
            return color
        }
        return palette.accent
    }

    // MARK: - 설정 UI용 접근자 (설정 '테마' 섹션이 이 두 값만 바꾸면 즉시 반영)

    /// 선택 팔레트 id. 프리셋 갤러리에서 지정.
    var selectedThemeID: String {
        get { settings.selectedThemeID }
        set { settings.selectedThemeID = newValue }
    }

    /// 강조색 오버라이드 "#RRGGBB". nil = 팔레트 기본 강조색 사용.
    var accentColorHex: String? {
        get { settings.accentColorHex }
        set { settings.accentColorHex = newValue }
    }
}
