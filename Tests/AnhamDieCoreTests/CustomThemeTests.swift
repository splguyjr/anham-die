import Foundation
import SwiftUI
import Testing
@testable import AnhamDieApp

// v7 §15.1·§15.2 스캐폴드 계약 테스트 — 커스텀 테마 모델/영속/해석 + 무채 렌더 헬퍼.

@Suite("CustomTheme 모델")
struct CustomThemeModelTests {
    private func sample(id: UUID = UUID()) -> CustomTheme {
        CustomTheme.from(palette: .sepia, name: "내 세피아", id: id)
    }

    @Test("JSON 인코딩 → 디코딩 왕복 보존")
    func jsonRoundTrip() throws {
        let themes = [sample(), CustomTheme.from(palette: .dark, name: "밤")]
        let data = try JSONEncoder().encode(themes)
        let decoded = try JSONDecoder().decode([CustomTheme].self, from: data)
        #expect(decoded == themes)
    }

    @Test("from(palette:)는 12슬롯을 hex로 캡처하고 base를 기록")
    func fromPaletteCapturesSlots() {
        let theme = sample()
        #expect(theme.baseThemeID == "sepia")
        #expect(theme.isDark == ThemePalette.sepia.isDark)
        for slot in ThemeColorSlot.allCases {
            #expect(theme[slot] == ColorHex.hex(ThemePalette.sepia[keyPath: slot.paletteKeyPath]))
        }
    }

    @Test("palette() 변환 — id는 UUID 문자열, monochrome은 항상 false, 슬롯 hex 왕복 보존")
    func paletteConversion() {
        let id = UUID()
        var theme = sample(id: id)
        theme.accent = "#3A7BD5"
        let palette = theme.palette()
        #expect(palette.id == id.uuidString)
        #expect(palette.displayName == "내 세피아")
        #expect(!palette.monochrome)
        #expect(ColorHex.hex(palette.accent) == "#3A7BD5")
        for slot in ThemeColorSlot.allCases {
            #expect(ColorHex.hex(palette[keyPath: slot.paletteKeyPath]) == theme[slot].uppercased())
        }
    }

    @Test("파싱 불가 슬롯은 베이스 프리셋 값으로 폴백")
    func invalidSlotFallsBackToBase() {
        var theme = sample()
        theme.background = "망가진값"
        let palette = theme.palette()
        #expect(palette.background == ThemePalette.sepia.background)
    }

    @Test("미상 baseThemeID는 기본 프리셋으로 폴백")
    func unknownBaseFallsBack() {
        var theme = sample()
        theme.baseThemeID = "없는프리셋"
        #expect(theme.basePalette.id == ThemePalette.defaultLight.id)
    }

    @Test("resetSlot은 슬롯을 베이스 프리셋 hex로 되돌린다")
    func resetSlotRestoresBase() {
        var theme = sample()
        theme[.accent] = "#010203"
        theme.resetSlot(.accent)
        #expect(theme.accent == ColorHex.hex(ThemePalette.sepia.accent))
    }

    @Test("슬롯 열거는 12개이고 표시명이 유일")
    func twelveDistinctSlots() {
        #expect(ThemeColorSlot.allCases.count == 12)
        let names = ThemeColorSlot.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
    }
}

@Suite("AppSettings customThemes 영속·CRUD")
struct CustomThemePersistenceTests {
    @Test("추가/갱신/삭제/복제 + 재로드 왕복")
    func crudAndReload() throws {
        let suite = "AnhamDieTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)

        let theme = CustomTheme.from(palette: .forest, name: "숲")
        settings.addCustomTheme(theme)
        #expect(settings.customTheme(id: theme.id) == theme)

        var edited = theme
        edited.name = "깊은 숲"
        edited.accent = "#112233"
        settings.updateCustomTheme(edited)
        #expect(settings.customTheme(id: theme.id)?.name == "깊은 숲")

        let copy = try #require(settings.duplicateCustomTheme(id: theme.id))
        #expect(copy.id != theme.id)
        #expect(copy.name == "깊은 숲 복사본")
        #expect(copy.accent == "#112233")
        #expect(settings.customThemes.count == 2)

        // 같은 defaults로 재로드 — JSON 영속 확인
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.customThemes == settings.customThemes)

        settings.removeCustomTheme(id: copy.id)
        settings.removeCustomTheme(id: theme.id)
        #expect(settings.customThemes.isEmpty)
        #expect(AppSettings(defaults: defaults).customThemes.isEmpty)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("미상 id 갱신/복제는 무시된다")
    func unknownIDIsIgnored() {
        let settings = makeTestSettings()
        settings.updateCustomTheme(CustomTheme.from(palette: .dark, name: "유령"))
        #expect(settings.customThemes.isEmpty)
        #expect(settings.duplicateCustomTheme(id: UUID()) == nil)
    }
}

@MainActor
@Suite("ThemeManager 커스텀 해석·폴백")
struct ThemeManagerCustomTests {
    private func makeManager() -> (ThemeManager, AppSettings) {
        let settings = makeTestSettings()
        return (ThemeManager(settings: settings), settings)
    }

    @Test("커스텀 UUID 선택 시 12슬롯 hex가 팔레트로 반영")
    func customSelectionResolves() {
        let (manager, settings) = makeManager()
        var theme = CustomTheme.from(palette: .defaultLight, name: "나만의")
        theme.accent = "#AB4321"
        settings.addCustomTheme(theme)
        settings.selectedThemeID = theme.id.uuidString
        #expect(manager.isCustomThemeSelected)
        #expect(manager.selectedCustomTheme == theme)
        #expect(manager.palette.id == theme.id.uuidString)
        #expect(ColorHex.hex(manager.palette.accent) == "#AB4321")
        #expect(!manager.palette.monochrome)
    }

    @Test("삭제된 커스텀 id는 기본 프리셋으로 폴백")
    func deletedCustomFallsBack() {
        let (manager, settings) = makeManager()
        settings.selectedThemeID = UUID().uuidString
        #expect(!manager.isCustomThemeSelected)
        #expect(manager.palette.id == ThemePalette.defaultLight.id)
    }

    @Test("deleteCustomTheme — 선택 중이던 테마 삭제 시 selectedThemeID도 기본 폴백")
    func deleteResetsSelection() {
        let (manager, settings) = makeManager()
        let theme = manager.createCustomTheme(basedOn: "dark")
        settings.selectedThemeID = theme.id.uuidString
        manager.deleteCustomTheme(id: theme.id)
        #expect(settings.customThemes.isEmpty)
        #expect(settings.selectedThemeID == AppSettings.defaultThemeID)
    }

    @Test("deleteCustomTheme — 선택 중이 아니면 selectedThemeID 유지")
    func deleteKeepsOtherSelection() {
        let (manager, settings) = makeManager()
        let theme = manager.createCustomTheme(basedOn: "sepia")
        settings.selectedThemeID = "sepia"
        manager.deleteCustomTheme(id: theme.id)
        #expect(settings.selectedThemeID == "sepia")
    }

    @Test("createCustomTheme — 프리셋 복제, 커스텀 복제 시 baseThemeID 승계")
    func createInheritsBase() {
        let (manager, settings) = makeManager()
        let first = manager.createCustomTheme(basedOn: "forest")
        #expect(first.baseThemeID == "forest")
        #expect(first.name == "포레스트 복사본")
        let second = manager.createCustomTheme(basedOn: first.id.uuidString, name: "숲2")
        #expect(second.baseThemeID == "forest")
        #expect(second.name == "숲2")
        #expect(settings.customThemes.count == 2)
    }

    @Test("updateCustomTheme — 편집이 즉시 palette에 반영 (실시간 계약)")
    func updateReflectsImmediately() {
        let (manager, settings) = makeManager()
        var theme = manager.createCustomTheme(basedOn: "default")
        settings.selectedThemeID = theme.id.uuidString
        theme.background = "#101010"
        theme.isDark = true
        manager.updateCustomTheme(theme)
        #expect(ColorHex.hex(manager.palette.background) == "#101010")
        #expect(manager.palette.isDark)
    }

    @Test("회귀: 프리셋 선택 시 accentColorHex 오버라이드는 v5와 동일 동작")
    func presetAccentOverrideRegression() {
        let (manager, settings) = makeManager()
        settings.selectedThemeID = "default"
        settings.accentColorHex = "#FF0000"
        #expect(manager.accent == ColorHex.color("#FF0000"))
    }

    @Test("커스텀 선택 시 accentColorHex 오버라이드는 무시되고 accent 슬롯 사용")
    func customIgnoresAccentOverride() {
        let (manager, settings) = makeManager()
        var theme = manager.createCustomTheme(basedOn: "default")
        theme.accent = "#00AA55"
        manager.updateCustomTheme(theme)
        settings.selectedThemeID = theme.id.uuidString
        settings.accentColorHex = "#FF0000"
        #expect(manager.accent == ColorHex.color("#00AA55"))
    }
}

@MainActor
@Suite("무채 렌더 계약 (§15.2)")
struct MonochromeContractTests {
    private func makeManager(themeID: String) -> ThemeManager {
        let settings = makeTestSettings()
        settings.selectedThemeID = themeID
        return ThemeManager(settings: settings)
    }

    @Test("monochrome 플래그는 모노 프리셋만 true, 커스텀 변환은 항상 false")
    func monochromeFlagScope() {
        for palette in ThemePalette.all {
            #expect(palette.monochrome == (palette.id == "mono"))
        }
        #expect(!CustomTheme.from(palette: .mono, name: "모노복제").palette().monochrome)
    }

    @Test("모노: 태그 색은 사용자 hex 무시하고 회색조(textSecondary)")
    func monoTagColorIsGray() {
        let manager = makeManager(themeID: "mono")
        #expect(manager.resolvedTagColor(hex: "#FF0000") == manager.palette.textSecondary)
        #expect(manager.resolvedTagColor(Tag(name: "빨강", colorHex: "#FF0000"))
            == manager.palette.textSecondary)
    }

    @Test("비모노: 태그 색은 기존과 동일 — hex 파싱, 실패 시 textDisabled 폴백")
    func nonMonoTagColorUnchanged() {
        let manager = makeManager(themeID: "default")
        #expect(manager.resolvedTagColor(hex: "#FF0000") == ColorHex.color("#FF0000"))
        #expect(manager.resolvedTagColor(hex: "망가짐") == manager.palette.textDisabled)
    }

    @Test("모노: 우선순위 막대는 농도·폭으로 구분 (빨강 없음, 높음이 가장 두껍다)")
    func monoPriorityStyles() {
        let manager = makeManager(themeID: "mono")
        let high = manager.resolvedPriorityStyle(.high)
        let normal = manager.resolvedPriorityStyle(.normal)
        let low = manager.resolvedPriorityStyle(.low)
        #expect(high != normal && normal != low && high != low)
        #expect(high.width > normal.width && normal.width > low.width)
        #expect(high.color != manager.palette.overdue)
    }

    @Test("비모노: 우선순위 막대는 v5 priorityBarColor와 동일 색, 폭 3")
    func nonMonoPriorityUnchanged() {
        let manager = makeManager(themeID: "forest")
        let p = manager.palette
        #expect(manager.resolvedPriorityStyle(.high) == PriorityBarStyle(color: p.overdue, width: 3))
        #expect(manager.resolvedPriorityStyle(.normal) == PriorityBarStyle(color: p.divider, width: 3))
        #expect(manager.resolvedPriorityStyle(.low)
            == PriorityBarStyle(color: p.textDisabled.opacity(0.5), width: 3))
    }

    @Test("모노 프리셋도 overdue는 빨강 유지 (위험 신호 — dueColor 경로)")
    func monoKeepsOverdueRed() {
        // overdue 슬롯이 회색이 아님을 hex 성분으로 확인 (R이 G·B보다 뚜렷이 크다)
        let hex = ColorHex.hex(ThemePalette.mono.overdue)
        let value = UInt64(hex.dropFirst(), radix: 16)!
        let r = Double((value & 0xFF0000) >> 16)
        let g = Double((value & 0x00FF00) >> 8)
        let b = Double(value & 0x0000FF)
        #expect(r > g + 40 && r > b + 40)
    }

    // 캘린더 요일색 계약(§15.2 "캘린더 전부" — 엄격 해석): 모노에서는 요일 관례색(일 빨강·토 파랑)도
    // 크롬으로 보고 무채(textPrimary)로 흡수한다. 빨강은 overdue 위험 신호 전용 —
    // 요일 관례 빨강이 남으면 전체 회색조 UI에서 overdue 신호와 구분되지 않는다.

    @Test("모노: 캘린더 요일색은 일·토 모두 무채 textPrimary, 평일은 base 유지")
    func monoWeekdayColorsAchromatic() {
        let p = ThemePalette.mono
        #expect(CalendarPalette.sunday(in: p) == p.textPrimary)
        #expect(CalendarPalette.saturday(in: p) == p.textPrimary)
        #expect(CalendarPalette.sunday(in: p) != p.overdue)
        let base = p.textSecondary
        #expect(CalendarPalette.weekdayColor(1, base: base, in: p) == p.textPrimary)
        #expect(CalendarPalette.weekdayColor(7, base: base, in: p) == p.textPrimary)
        for weekday in 2...6 {
            #expect(CalendarPalette.weekdayColor(weekday, base: base, in: p) == base)
        }
    }

    @Test("비모노: 요일색 회귀 없음 — 일=overdue 재사용, 토=isDark 2단 유채 파랑")
    func nonMonoWeekdayColorsUnchanged() {
        for p in [ThemePalette.defaultLight, .sepia, .forest, .dark, .midnight] {
            #expect(CalendarPalette.sunday(in: p) == p.overdue)
            let saturday = p.isDark
                ? Color(.sRGB, red: 0.42, green: 0.62, blue: 1.0, opacity: 1)
                : Color(.sRGB, red: 0.16, green: 0.38, blue: 0.78, opacity: 1)
            #expect(CalendarPalette.saturday(in: p) == saturday)
            #expect(CalendarPalette.weekdayColor(1, base: p.textSecondary, in: p) == p.overdue)
            #expect(CalendarPalette.weekdayColor(7, base: p.textSecondary, in: p) == saturday)
            #expect(CalendarPalette.weekdayColor(3, base: p.textSecondary, in: p) == p.textSecondary)
        }
    }
}
