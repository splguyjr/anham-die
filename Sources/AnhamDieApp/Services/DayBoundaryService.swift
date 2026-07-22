import Foundation

/// 논리적 하루 계산의 단일 소스. 하루는 자정이 아니라 기준 시각(기본 09:00)에 시작한다.
/// "논리적 날짜"는 해당 논리적 하루가 속한 달력 날짜의 startOfDay(자정) Date로 표현한다.
/// 모든 모듈(메인/오버레이/브리핑/이월)은 날짜 비교에 반드시 이 서비스를 써야 한다.
final class DayBoundaryService {
    private let settings: AppSettings
    let calendar: Calendar
    /// 테스트에서 현재 시각을 주입하기 위한 클로저
    var now: () -> Date

    init(settings: AppSettings, calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.settings = settings
        self.calendar = calendar
        self.now = now
    }

    /// 자정으로부터 기준 시각까지의 오프셋(초)
    var boundaryOffset: TimeInterval {
        TimeInterval(settings.dayBoundaryHour * 3600 + settings.dayBoundaryMinute * 60)
    }

    /// 주어진 시각이 속한 논리적 날짜(자정 정규화). 기준 시각 정각은 새 하루에 속한다.
    func logicalDate(of date: Date) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(-boundaryOffset))
    }

    func logicalToday() -> Date {
        logicalDate(of: now())
    }

    func logicalYesterday() -> Date {
        calendar.date(byAdding: .day, value: -1, to: logicalToday())!
    }

    /// 논리적 날짜 day의 하루가 실제로 시작되는 시각 (day 자정 + 기준 시각 오프셋)
    func startOfLogicalDay(_ day: Date) -> Date {
        calendar.startOfDay(for: day).addingTimeInterval(boundaryOffset)
    }

    /// 주어진 시각(기본: 현재) 이후에 논리적 하루가 바뀌는 다음 경계 시각
    func nextBoundaryDate(after date: Date? = nil) -> Date {
        let reference = date ?? now()
        let day = logicalDate(of: reference)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        return startOfLogicalDay(nextDay)
    }

    func isSameLogicalDay(_ a: Date, _ b: Date) -> Bool {
        logicalDate(of: a) == logicalDate(of: b)
    }

    /// D-day: due의 논리적 날짜 - 기준일의 논리적 날짜 (일 단위). 0=오늘, 음수=지남
    func dDay(of dueDate: Date, from reference: Date? = nil) -> Int {
        let ref = reference ?? now()
        let from = logicalDate(of: ref)
        let to = logicalDate(of: dueDate)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}
