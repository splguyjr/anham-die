import SwiftUI

/// v7 사용자 커스텀 테마 (PLAN §15.1) — 12색 슬롯을 hex 문자열("#RRGGBB")로 보관하는 저장형 모델.
/// AppSettings.customThemes에 JSON 배열로 영속되고, ThemeManager가 selectedThemeID(UUID 문자열)로
/// 해석해 palette()로 ThemePalette를 만든다. 커스텀 테마는 monochrome을 갖지 않는다(항상 false).
struct CustomTheme: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var isDark: Bool
    /// 슬롯별 ↺ 리셋의 기준 프리셋 id. 미상 id는 ThemePalette.preset(for:) 규약대로 기본 프리셋.
    var baseThemeID: String

    // 12색 슬롯 (배경/표면/보조 표면/텍스트 기본·보조·비활성/구분선/강조/지남/오늘/임박/여유)
    var background: String
    var surface: String
    var surfaceSecondary: String
    var textPrimary: String
    var textSecondary: String
    var textDisabled: String
    var divider: String
    var accent: String
    var overdue: String
    var dueToday: String
    var dueSoon: String
    var dueRelaxed: String

    init(
        id: UUID = UUID(), name: String, isDark: Bool, baseThemeID: String,
        background: String, surface: String, surfaceSecondary: String,
        textPrimary: String, textSecondary: String, textDisabled: String,
        divider: String, accent: String,
        overdue: String, dueToday: String, dueSoon: String, dueRelaxed: String
    ) {
        self.id = id
        self.name = name
        self.isDark = isDark
        self.baseThemeID = baseThemeID
        self.background = background
        self.surface = surface
        self.surfaceSecondary = surfaceSecondary
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textDisabled = textDisabled
        self.divider = divider
        self.accent = accent
        self.overdue = overdue
        self.dueToday = dueToday
        self.dueSoon = dueSoon
        self.dueRelaxed = dueRelaxed
    }

    /// 팔레트(프리셋 또는 다른 커스텀의 palette())를 복제해 커스텀 테마 생성 — "복제해서 편집" 흐름의 출발점.
    /// baseThemeID는 슬롯 리셋 기준이므로 프리셋 id를 넘겨야 한다(커스텀 복제 시 원본의 baseThemeID 승계).
    static func from(
        palette: ThemePalette, name: String, baseThemeID: String? = nil, id: UUID = UUID()
    ) -> CustomTheme {
        CustomTheme(
            id: id, name: name, isDark: palette.isDark,
            baseThemeID: baseThemeID ?? palette.id,
            background: ColorHex.hex(palette.background),
            surface: ColorHex.hex(palette.surface),
            surfaceSecondary: ColorHex.hex(palette.surfaceSecondary),
            textPrimary: ColorHex.hex(palette.textPrimary),
            textSecondary: ColorHex.hex(palette.textSecondary),
            textDisabled: ColorHex.hex(palette.textDisabled),
            divider: ColorHex.hex(palette.divider),
            accent: ColorHex.hex(palette.accent),
            overdue: ColorHex.hex(palette.overdue),
            dueToday: ColorHex.hex(palette.dueToday),
            dueSoon: ColorHex.hex(palette.dueSoon),
            dueRelaxed: ColorHex.hex(palette.dueRelaxed)
        )
    }

    /// 슬롯 리셋 기준 프리셋 (미상 baseThemeID는 기본 프리셋 폴백).
    var basePalette: ThemePalette { ThemePalette.preset(for: baseThemeID) }

    /// 12슬롯 hex → ThemePalette 변환. id는 UUID 문자열, monochrome은 항상 false(§15.1).
    /// 파싱 실패 슬롯은 베이스 프리셋 값으로 폴백해 화면이 깨지지 않게 한다.
    func palette() -> ThemePalette {
        let base = basePalette
        func c(_ hex: String, _ fallback: Color) -> Color { ColorHex.color(hex) ?? fallback }
        return ThemePalette(
            id: id.uuidString, displayName: name, isDark: isDark,
            background: c(background, base.background),
            surface: c(surface, base.surface),
            surfaceSecondary: c(surfaceSecondary, base.surfaceSecondary),
            textPrimary: c(textPrimary, base.textPrimary),
            textSecondary: c(textSecondary, base.textSecondary),
            textDisabled: c(textDisabled, base.textDisabled),
            divider: c(divider, base.divider),
            accent: c(accent, base.accent),
            overdue: c(overdue, base.overdue),
            dueToday: c(dueToday, base.dueToday),
            dueSoon: c(dueSoon, base.dueSoon),
            dueRelaxed: c(dueRelaxed, base.dueRelaxed),
            monochrome: false
        )
    }

    /// 슬롯 단위 접근 — 편집기의 12개 ColorPicker가 keyPath 분기 없이 순회할 수 있게 한다.
    subscript(slot: ThemeColorSlot) -> String {
        get { self[keyPath: slot.customKeyPath] }
        set { self[keyPath: slot.customKeyPath] = newValue }
    }

    /// 슬롯별 ↺ 리셋 — 베이스 프리셋의 해당 슬롯 hex로 되돌린다 (§15.1).
    mutating func resetSlot(_ slot: ThemeColorSlot) {
        self[slot] = ColorHex.hex(basePalette[keyPath: slot.paletteKeyPath])
    }
}

/// 12색 슬롯 열거 — 편집기(ColorPicker 나열·리셋 버튼)와 썸네일이 공유하는 슬롯 계약 (§15.1).
enum ThemeColorSlot: String, CaseIterable, Identifiable, Sendable {
    case background, surface, surfaceSecondary
    case textPrimary, textSecondary, textDisabled
    case divider, accent
    case overdue, dueToday, dueSoon, dueRelaxed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .background: return "배경"
        case .surface: return "표면"
        case .surfaceSecondary: return "보조 표면"
        case .textPrimary: return "텍스트 기본"
        case .textSecondary: return "텍스트 보조"
        case .textDisabled: return "텍스트 비활성"
        case .divider: return "구분선"
        case .accent: return "강조"
        case .overdue: return "지남"
        case .dueToday: return "오늘"
        case .dueSoon: return "임박"
        case .dueRelaxed: return "여유"
        }
    }

    var customKeyPath: WritableKeyPath<CustomTheme, String> {
        switch self {
        case .background: return \.background
        case .surface: return \.surface
        case .surfaceSecondary: return \.surfaceSecondary
        case .textPrimary: return \.textPrimary
        case .textSecondary: return \.textSecondary
        case .textDisabled: return \.textDisabled
        case .divider: return \.divider
        case .accent: return \.accent
        case .overdue: return \.overdue
        case .dueToday: return \.dueToday
        case .dueSoon: return \.dueSoon
        case .dueRelaxed: return \.dueRelaxed
        }
    }

    var paletteKeyPath: KeyPath<ThemePalette, Color> {
        switch self {
        case .background: return \.background
        case .surface: return \.surface
        case .surfaceSecondary: return \.surfaceSecondary
        case .textPrimary: return \.textPrimary
        case .textSecondary: return \.textSecondary
        case .textDisabled: return \.textDisabled
        case .divider: return \.divider
        case .accent: return \.accent
        case .overdue: return \.overdue
        case .dueToday: return \.dueToday
        case .dueSoon: return \.dueSoon
        case .dueRelaxed: return \.dueRelaxed
        }
    }
}
