import Foundation

// 캘린더 다중 뷰 (PLAN §12.1): 월/주/일 뷰 모드 + 뷰 단위 날짜 범위·이동 계산,
// 주간 7열(일~토) 레이아웃, 일간 단일일 조회. 저장 키는 AppSettings.calendarViewMode.

/// 캘린더 뷰 모드. rawValue는 AppSettings 영속·복원 키로 쓰이므로 변경 금지.
enum CalendarViewMode: String, CaseIterable, Codable, Sendable {
    case month
    case week
    case day

    var displayName: String {
        switch self {
        case .month: return "월"
        case .week: return "주"
        case .day: return "일"
        }
    }

    /// ◀/▶ 이동 단위 (뷰 종류에 따라 달/주/일).
    var navigationComponent: Calendar.Component {
        switch self {
        case .month: return .month
        case .week: return .weekOfYear
        case .day: return .day
        }
    }

    /// 현재 뷰가 포함하는 날짜 범위 [start, end) — start는 자정, end는 배타적.
    /// month: 그 달 1일~다음 달 1일 / week: 주 시작(firstWeekday)~+7일 / day: 그날 자정~다음날 자정.
    func dateRange(containing date: Date, calendar: Calendar) -> Range<Date> {
        switch self {
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
                ?? calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return start..<end
        case .week:
            let start = Self.weekStart(containing: date, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return start..<end
        case .day:
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return start..<end
        }
    }

    /// ◀/▶/오늘 이동: 뷰 단위로 delta만큼 앞뒤로 옮긴 기준 날짜(자정 정규화).
    func shifted(_ date: Date, by delta: Int, calendar: Calendar) -> Date {
        let base = calendar.startOfDay(for: date)
        return calendar.date(byAdding: navigationComponent, value: delta, to: base) ?? base
    }

    /// 주의 시작(firstWeekday) 자정. 일요일 시작 로케일이면 그 주 일요일.
    static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: startOfDay) ?? startOfDay
    }
}

/// 주간 7열(일~토) 레이아웃. firstWeekday 기준으로 열 순서와 한국어 요일 약칭을 회전한다.
struct WeekLayout {
    /// 주 시작 자정 (firstWeekday 기준).
    let weekStart: Date
    /// 7개 날짜(자정), 좌→우 열 순서.
    let days: [Date]
    /// days와 같은 순서의 요일 약칭 ["일","월",...].
    let weekdaySymbols: [String]

    private static let koreanWeekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    init(containing date: Date, calendar: Calendar) {
        let start = CalendarViewMode.weekStart(containing: date, calendar: calendar)
        self.weekStart = start
        self.days = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start) ?? start }
        self.weekdaySymbols = (0..<7).map {
            Self.koreanWeekdaySymbols[(calendar.firstWeekday - 1 + $0) % 7]
        }
    }
}

extension TaskStore {
    /// 주간 뷰용 7열 그룹 — 각 열은 그날의 tasks(on:) 목록(전역 표시 순서 정렬).
    /// 열 간 드래그 = scheduledDate 변경은 캘린더 셀 드래그(CalendarTaskDrag)와 동일 규약으로 UI에서 처리.
    func weekColumns(
        containing date: Date,
        boundary: DayBoundaryService
    ) -> [(day: Date, tasks: [TodoTask])] {
        WeekLayout(containing: date, calendar: boundary.calendar).days.map { day in
            (day: day, tasks: tasks(on: day, boundary: boundary))
        }
    }

    /// 일간 뷰용 단일일 조회. tasks(on:)의 얇은 별칭 — 뷰 호출부 가독성용.
    func dayColumn(on day: Date, boundary: DayBoundaryService) -> [TodoTask] {
        tasks(on: boundary.calendar.startOfDay(for: day), boundary: boundary)
    }
}
