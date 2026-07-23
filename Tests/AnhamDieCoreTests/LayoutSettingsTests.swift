import Foundation
import Testing
@testable import AnhamDieApp

// PLAN §12.2·§12.3 — 레이아웃 상태 영속: 캘린더 뷰 모드·패널 폭·사이드바 접힘.

@MainActor
@Suite("레이아웃 상태 저장·복원")
struct LayoutSettingsTests {
    private func freshDefaults() -> (UserDefaults, String) {
        let suite = "AnhamDieTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    @Test("기본값: 월 뷰·패널 폭 기본·사이드바 펼침")
    func defaults() {
        let (defaults, _) = freshDefaults()
        let s = AppSettings(defaults: defaults)
        #expect(s.calendarViewMode == .month)
        #expect(s.calendarPanelWidth == AppSettings.calendarPanelWidthDefault)
        #expect(s.sidebarCollapsed == false)
    }

    @Test("calendarViewMode 라운드트립")
    func viewModeRoundTrips() {
        let (defaults, _) = freshDefaults()
        let s = AppSettings(defaults: defaults)
        s.calendarViewMode = .week
        #expect(AppSettings(defaults: defaults).calendarViewMode == .week)
        s.calendarViewMode = .day
        #expect(AppSettings(defaults: defaults).calendarViewMode == .day)
    }

    @Test("calendarPanelWidth 라운드트립")
    func panelWidthRoundTrips() {
        let (defaults, _) = freshDefaults()
        let s = AppSettings(defaults: defaults)
        s.calendarPanelWidth = 360
        #expect(AppSettings(defaults: defaults).calendarPanelWidth == 360)
    }

    @Test("calendarPanelWidth는 범위로 클램프된다")
    func panelWidthClamps() {
        let (defaults, _) = freshDefaults()
        let s = AppSettings(defaults: defaults)
        s.calendarPanelWidth = 9999
        #expect(s.calendarPanelWidth == AppSettings.calendarPanelWidthRange.upperBound)
        s.calendarPanelWidth = 10
        #expect(s.calendarPanelWidth == AppSettings.calendarPanelWidthRange.lowerBound)
        // 클램프된 값이 영속·복원되는지
        #expect(AppSettings(defaults: defaults).calendarPanelWidth
            == AppSettings.calendarPanelWidthRange.lowerBound)
    }

    @Test("sidebarCollapsed 라운드트립")
    func sidebarCollapsedRoundTrips() {
        let (defaults, _) = freshDefaults()
        let s = AppSettings(defaults: defaults)
        s.sidebarCollapsed = true
        #expect(AppSettings(defaults: defaults).sidebarCollapsed == true)
    }
}
