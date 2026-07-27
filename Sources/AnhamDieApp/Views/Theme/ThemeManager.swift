import Observation
import SwiftUI

/// v5 우선순위 막대 렌더 스타일 (v7 §15.2 확장) — 색 + 폭.
/// monochrome 팔레트에서는 색 농도·폭으로 높음/보통/낮음을 구분하므로 폭이 계약에 포함된다.
struct PriorityBarStyle: Equatable {
    var color: Color
    var width: CGFloat
}

/// v5 동적 테마 (PLAN §13.2, v7 §15 확장) — 현재 팔레트 + 사용자 강조색 오버라이드를 결합해
/// 앱 전역에 실시간 색을 공급한다. AppSettings에 선택 팔레트·강조색·커스텀 테마 목록을 영속하고,
/// AppTheme.* 색 참조가 전부 이 매니저(전역 shared)를 경유한다.
///
/// 반응성: 색 접근이 `settings.selectedThemeID`/`settings.accentColorHex`/`settings.customThemes`
/// (모두 @Observable 저장 프로퍼티) 읽기로 귀결되므로, SwiftUI body에서 AppTheme.* 를 읽는 것만으로
/// 관찰이 등록된다 → 설정 변경·커스텀 테마 편집 시 전 화면이 재평가된다(추가 배선 불필요).
@Observable
final class ThemeManager {
    /// AppTheme.* 정적 색이 참조하는 전역 인스턴스. AppContext.theme와 동일 객체.
    static let shared = ThemeManager(settings: .shared)

    @ObservationIgnored let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - 해석 (프리셋 id · 커스텀 UUID → ThemePalette)

    /// 현재 선택된 팔레트. selectedThemeID가 프리셋 id면 프리셋, 커스텀 UUID면 12슬롯 hex를
    /// 변환한 팔레트(monochrome=false). 미상/삭제된 id는 기본 프리셋 폴백 (§15.1).
    var palette: ThemePalette {
        resolvedPalette(for: settings.selectedThemeID)
    }

    /// id 해석 단일 진입점 — 갤러리 썸네일 등이 임의 id의 팔레트를 미리 볼 때도 쓴다.
    /// 프리셋 id는 UUID 형식이 아니므로 두 이름공간이 충돌하지 않는다.
    func resolvedPalette(for id: String) -> ThemePalette {
        if let uuid = UUID(uuidString: id), let custom = settings.customTheme(id: uuid) {
            return custom.palette()
        }
        return ThemePalette.preset(for: id)
    }

    /// 현재 선택이 (존재하는) 커스텀 테마인지. 삭제돼 폴백 중인 UUID는 false.
    var isCustomThemeSelected: Bool {
        selectedCustomTheme != nil
    }

    /// 현재 선택된 커스텀 테마 (프리셋 선택·삭제된 UUID면 nil) — 편집기 진입점.
    var selectedCustomTheme: CustomTheme? {
        UUID(uuidString: settings.selectedThemeID).flatMap { settings.customTheme(id: $0) }
    }

    /// 최종 강조색 — 프리셋 선택 시 사용자 오버라이드(#RRGGBB)가 있으면 그것(v5와 동일, 회귀 금지).
    /// 커스텀 테마 선택 시에는 accent 슬롯이 곧 사용자의 선택이므로 간이 오버라이드를 무시한다.
    var accent: Color {
        if !isCustomThemeSelected,
           let hex = settings.accentColorHex, let color = ColorHex.color(hex) {
            return color
        }
        return palette.accent
    }

    // MARK: - 무채 렌더 계약 (§15.2 — 적용은 각 모듈이 담당)

    /// 태그 칩 tint. monochrome 팔레트면 사용자 지정 hex를 무시하고 회색조(textSecondary),
    /// 아니면 기존과 동일하게 hex 파싱(실패 시 textDisabled 폴백).
    func resolvedTagColor(hex: String) -> Color {
        let p = palette
        if p.monochrome { return p.textSecondary }
        return ColorHex.color(hex) ?? p.textDisabled
    }

    func resolvedTagColor(_ tag: Tag) -> Color {
        resolvedTagColor(hex: tag.colorHex)
    }

    /// 우선순위 막대 스타일. monochrome이면 회색 농도+폭으로 높음/보통/낮음 구분(빨강 없음 —
    /// overdue 유지 규칙은 D-day 신호에만 해당), 아니면 v5 색·폭 3pt 그대로.
    func resolvedPriorityStyle(_ priority: Priority) -> PriorityBarStyle {
        let p = palette
        if p.monochrome {
            switch priority {
            case .high: return PriorityBarStyle(color: p.textPrimary.opacity(0.85), width: 4)
            case .normal: return PriorityBarStyle(color: p.textSecondary.opacity(0.55), width: 3)
            case .low: return PriorityBarStyle(color: p.textDisabled.opacity(0.45), width: 2)
            }
        }
        switch priority {
        case .high: return PriorityBarStyle(color: p.overdue, width: 3)
        case .normal: return PriorityBarStyle(color: p.divider, width: 3)
        case .low: return PriorityBarStyle(color: p.textDisabled.opacity(0.5), width: 3)
        }
    }

    // MARK: - 커스텀 테마 CRUD (§15.1 — 저장은 AppSettings.customThemes, 선택 규칙은 여기서)

    var customThemes: [CustomTheme] { settings.customThemes }

    /// "복제해서 편집" — sourceID(프리셋 id 또는 커스텀 UUID)의 팔레트를 복제한 커스텀 테마를
    /// 목록에 추가하고 반환. 선택 전환은 호출측 몫. baseThemeID는 항상 프리셋 id가 되도록
    /// 커스텀 원본이면 그 baseThemeID를 승계한다.
    @discardableResult
    func createCustomTheme(basedOn sourceID: String, name: String? = nil) -> CustomTheme {
        let source = resolvedPalette(for: sourceID)
        let baseID: String
        if let uuid = UUID(uuidString: sourceID), let custom = settings.customTheme(id: uuid) {
            baseID = custom.baseThemeID
        } else {
            baseID = source.id
        }
        let theme = CustomTheme.from(
            palette: source, name: name ?? "\(source.displayName) 복사본", baseThemeID: baseID
        )
        settings.addCustomTheme(theme)
        return theme
    }

    /// 편집기 실시간 반영 — 교체 즉시 @Observable 경유로 전 화면 색이 갱신된다.
    func updateCustomTheme(_ theme: CustomTheme) {
        settings.updateCustomTheme(theme)
    }

    /// 삭제. 선택 중이던 테마를 지우면 selectedThemeID를 기본 프리셋으로 폴백 (§15.1).
    func deleteCustomTheme(id: UUID) {
        settings.removeCustomTheme(id: id)
        if settings.selectedThemeID == id.uuidString {
            settings.selectedThemeID = AppSettings.defaultThemeID
        }
    }

    @discardableResult
    func duplicateCustomTheme(id: UUID) -> CustomTheme? {
        settings.duplicateCustomTheme(id: id)
    }

    // MARK: - 설정 UI용 접근자 (설정 '테마' 섹션이 이 두 값만 바꾸면 즉시 반영)

    /// 선택 테마 id — 프리셋 id 또는 커스텀 UUID 문자열. 갤러리에서 지정.
    var selectedThemeID: String {
        get { settings.selectedThemeID }
        set { settings.selectedThemeID = newValue }
    }

    /// 강조색 오버라이드 "#RRGGBB". nil = 팔레트 기본 강조색 사용. (프리셋 선택 시에만 적용)
    var accentColorHex: String? {
        get { settings.accentColorHex }
        set { settings.accentColorHex = newValue }
    }
}
