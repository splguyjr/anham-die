import Foundation
import Testing
@testable import AnhamDieApp

// PLAN §12.1 — 캘린더 월/주/일 뷰: 날짜 범위·이동 계산, 주간 7열 레이아웃, 일간 단일일 조회.

@Suite("CalendarViewMode 날짜 범위·이동")
struct CalendarViewModeTests {
    /// firstWeekday=1(일요일 시작) 고정 그레고리력 — 주 계산 결정성 확보.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1
        c.timeZone = .current
        return c
    }

    // 2026-07-22는 수요일.
    private let refDay = midnight(2026, 7, 22)

    @Test("월 범위 = 그 달 1일 ~ 다음 달 1일")
    func monthRange() {
        let range = CalendarViewMode.month.dateRange(containing: midnight(2026, 7, 15), calendar: calendar)
        #expect(range.lowerBound == midnight(2026, 7, 1))
        #expect(range.upperBound == midnight(2026, 8, 1))
    }

    @Test("주 범위 = 그 주 일요일 ~ +7일 (일요일 시작)")
    func weekRange() {
        let range = CalendarViewMode.week.dateRange(containing: refDay, calendar: calendar)
        #expect(range.lowerBound == midnight(2026, 7, 19)) // 일요일
        #expect(range.upperBound == midnight(2026, 7, 26))
    }

    @Test("일 범위 = 그날 자정 ~ 다음날 자정")
    func dayRange() {
        let range = CalendarViewMode.day.dateRange(containing: date(2026, 7, 22, 15), calendar: calendar)
        #expect(range.lowerBound == midnight(2026, 7, 22))
        #expect(range.upperBound == midnight(2026, 7, 23))
    }

    @Test("이동: 뷰 단위(달/주/일)로 앞뒤 이동")
    func shiftByUnit() {
        #expect(CalendarViewMode.month.shifted(midnight(2026, 7, 22), by: 1, calendar: calendar)
            == midnight(2026, 8, 22))
        #expect(CalendarViewMode.month.shifted(midnight(2026, 7, 22), by: -1, calendar: calendar)
            == midnight(2026, 6, 22))
        #expect(CalendarViewMode.week.shifted(refDay, by: 1, calendar: calendar)
            == midnight(2026, 7, 29))
        #expect(CalendarViewMode.day.shifted(refDay, by: -1, calendar: calendar)
            == midnight(2026, 7, 21))
    }

    @Test("weekStart: 주 중간 날짜에서 그 주 일요일 반환")
    func weekStartComputation() {
        #expect(CalendarViewMode.weekStart(containing: refDay, calendar: calendar) == midnight(2026, 7, 19))
        // 일요일 자신은 그대로
        #expect(CalendarViewMode.weekStart(containing: midnight(2026, 7, 19), calendar: calendar)
            == midnight(2026, 7, 19))
    }

    @Test("WeekLayout: 7일·일요일 시작·한국어 요일 약칭")
    func weekLayout() {
        let layout = WeekLayout(containing: refDay, calendar: calendar)
        #expect(layout.days.count == 7)
        #expect(layout.weekStart == midnight(2026, 7, 19))
        #expect(layout.days.first == midnight(2026, 7, 19))
        #expect(layout.days.last == midnight(2026, 7, 25))
        #expect(layout.weekdaySymbols == ["일", "월", "화", "수", "목", "금", "토"])
    }

    @Test("rawValue 안정성 (영속 키) — month/week/day")
    func rawValueStable() {
        #expect(CalendarViewMode.month.rawValue == "month")
        #expect(CalendarViewMode.week.rawValue == "week")
        #expect(CalendarViewMode.day.rawValue == "day")
    }
}

@MainActor
@Suite("주간 7열·일간 단일일 조회")
struct WeekColumnsTests {
    private let store: JSONTaskStore
    private let boundary: DayBoundaryService
    private let refDay = midnight(2026, 7, 22)

    init() {
        store = makeTempStore()
        boundary = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
    }

    @Test("weekColumns: 7열, 각 열에 그날의 task가 배치된다")
    func weekColumnsGrouping() {
        let sun = TodoTask(title: "일요일", scheduledDate: midnight(2026, 7, 19))
        let wed = TodoTask(title: "수요일", scheduledDate: midnight(2026, 7, 22))
        store.addTask(sun)
        store.addTask(wed)

        let columns = store.weekColumns(containing: refDay, boundary: boundary)
        #expect(columns.count == 7)
        #expect(columns[0].day == midnight(2026, 7, 19))
        #expect(columns[0].tasks.map { $0.id } == [sun.id])
        #expect(columns[3].day == midnight(2026, 7, 22))
        #expect(columns[3].tasks.map { $0.id } == [wed.id])
        #expect(columns[1].tasks.isEmpty)
    }

    @Test("dayColumn: 단일일 조회는 tasks(on:)과 일치")
    func dayColumnMatchesTasksOn() {
        let wed = TodoTask(title: "수요일", scheduledDate: refDay)
        store.addTask(wed)
        #expect(store.dayColumn(on: refDay, boundary: boundary).map { $0.id }
            == store.tasks(on: refDay, boundary: boundary).map { $0.id })
        #expect(store.dayColumn(on: refDay, boundary: boundary).map { $0.id } == [wed.id])
    }
}

// §20.4 ③ — 주간 뷰 목표 스트립의 기준 주. anchor 요일이 아니라 표시 열의 다수 소속
// 논리적 주로 고정한다: 일간 뷰에서 일요일로 이동 후 주간 전환 시(anchor=일) 열은 일~토인데
// 스트립만 이전 논리적 주(월~일) 기록을 보여주던 비일관 회귀를 잠근다.
@MainActor
@Suite("주간 뷰 목표 스트립 기준 주")
struct CalendarWeekStripWeekTests {
    @Test("표시 열 다수의 논리적 주 — anchor 요일 비의존 (§20.4)")
    func stripWeekStartUsesMajorityLogicalWeek() {
        let settings = makeTestSettings(boundaryHour: 6) // 주 시작 기본 월(2)
        let boundary = DayBoundaryService(settings: settings, now: { date(2026, 8, 5, 12, 0) })
        // 달력 일요일 시작 표시 열: 8/2(일)~8/8(토) — 일요일 하루만 이전 논리적 주(7/27) 소속.
        let sundayLedDays = (0..<7).map { midnight(2026, 8, 2 + $0) }

        // anchor가 일요일이든 수요일이든 열이 같으면 스트립 주도 같다 — 다수(월~토 6일)의 주.
        #expect(CalendarWeekView.stripWeekStart(forDisplayDays: sundayLedDays, boundary: boundary)
            == midnight(2026, 8, 3))

        // 주 시작=일 설정이면 표시 열과 논리적 주가 일치 — 그대로 그 주(8/2).
        settings.weekStartDay = 1
        #expect(CalendarWeekView.stripWeekStart(forDisplayDays: sundayLedDays, boundary: boundary)
            == midnight(2026, 8, 2))
    }
}
