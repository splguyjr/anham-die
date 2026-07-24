import Foundation
import SwiftUI
import Testing
@testable import AnhamDieApp

@Suite("ThemePalette 해석")
struct ThemePaletteTests {
    @Test("기본 id는 기본 팔레트")
    func defaultResolves() {
        #expect(ThemePalette.preset(for: "default").id == "default")
        #expect(ThemePalette.preset(for: AppSettings.defaultThemeID).id == ThemePalette.defaultLight.id)
    }

    @Test("미상/삭제된 id는 기본으로 폴백")
    func unknownFallsBackToDefault() {
        #expect(ThemePalette.preset(for: "존재하지않는테마").id == ThemePalette.defaultLight.id)
        #expect(ThemePalette.preset(for: "").id == ThemePalette.defaultLight.id)
    }

    @Test("프리셋은 4개 이상이고 id가 유일하다")
    func presetsAreDistinct() {
        #expect(ThemePalette.all.count >= 4)
        let ids = ThemePalette.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("각 프리셋 id로 원본을 정확히 되찾는다")
    func everyPresetResolvesToItself() {
        for palette in ThemePalette.all {
            #expect(ThemePalette.preset(for: palette.id) == palette)
        }
    }

    @Test("다크 프리셋만 isDark")
    func onlyDarkIsDark() {
        #expect(ThemePalette.dark.isDark)
        #expect(!ThemePalette.defaultLight.isDark)
        #expect(!ThemePalette.sepia.isDark)
    }
}

@Suite("ColorHex 파싱")
struct ColorHexTests {
    @Test("유효한 hex 파싱")
    func validHex() {
        #expect(ColorHex.color("#FF0000") != nil)
        #expect(ColorHex.color("00FF00") != nil)
    }

    @Test("잘못된 hex는 nil")
    func invalidHex() {
        #expect(ColorHex.color("#FFF") == nil)
        #expect(ColorHex.color("zzzzzz") == nil)
        #expect(ColorHex.color("") == nil)
    }

    @Test("Color → hex → Color 왕복 보존")
    func roundTrip() {
        let hex = "#3A7BD5"
        let color = ColorHex.color(hex)
        #expect(color != nil)
        #expect(ColorHex.hex(color!).uppercased() == hex)
    }
}

@MainActor
@Suite("ThemeManager 강조색 결합")
struct ThemeManagerTests {
    private func makeManager() -> (ThemeManager, AppSettings) {
        let settings = makeTestSettings()
        return (ThemeManager(settings: settings), settings)
    }

    @Test("오버라이드 없으면 팔레트 기본 강조색")
    func accentDefaultsToPalette() {
        let (manager, settings) = makeManager()
        settings.selectedThemeID = "forest"
        settings.accentColorHex = nil
        #expect(manager.accent == ThemePalette.forest.accent)
    }

    @Test("유효한 오버라이드가 팔레트 강조색을 대체")
    func accentOverrideWins() {
        let (manager, settings) = makeManager()
        settings.selectedThemeID = "default"
        settings.accentColorHex = "#FF0000"
        #expect(manager.accent == ColorHex.color("#FF0000"))
        #expect(manager.accent != ThemePalette.defaultLight.accent)
    }

    @Test("잘못된 오버라이드는 팔레트 기본으로 폴백")
    func invalidOverrideFallsBack() {
        let (manager, settings) = makeManager()
        settings.selectedThemeID = "default"
        settings.accentColorHex = "nothex"
        #expect(manager.accent == ThemePalette.defaultLight.accent)
    }

    @Test("selectedThemeID 변경이 palette에 반영")
    func paletteFollowsSelection() {
        let (manager, settings) = makeManager()
        settings.selectedThemeID = "dark"
        #expect(manager.palette.id == "dark")
        #expect(manager.palette.isDark)
    }

    @Test("설정 접근자 왕복이 AppSettings에 영속")
    func accessorsPersist() {
        let (manager, settings) = makeManager()
        manager.selectedThemeID = "sepia"
        manager.accentColorHex = "#123456"
        #expect(settings.selectedThemeID == "sepia")
        #expect(settings.accentColorHex == "#123456")
    }
}
