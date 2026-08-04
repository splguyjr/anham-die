import Foundation

/// 논리적 하루 계산의 단일 소스. 하루는 자정이 아니라 기준 시각(기본 09:00)에 시작한다.
/// "논리적 날짜"는 해당 논리적 하루가 속한 달력 날짜의 startOfDay(자정) Date로 표현한다.
/// 모든 모듈(메인/오버레이/브리핑/이월)은 날짜 비교에 반드시 이 서비스를 써야 한다.
/// 해석 규칙: 실제 시각(now/completedAt 등 타임스탬프)은 logicalDate(of:),
/// 저장된 날짜 키(scheduledDate/dueDate)는 logicalDay(ofStored:).
/// 저장 값에 logicalDate(of:)를 쓰면 경계 설정을 바꾸는 순간 소속 날짜가 밀린다 (회귀 테스트 있음).
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

    /// 주어진 실제 시각(타임스탬프)이 속한 논리적 날짜(자정 정규화). 기준 시각 정각은 새 하루에 속한다.
    /// '현재' 경계 오프셋으로 해석하므로 scheduledDate/dueDate 같은 저장된 날짜 키에는 쓰지 말 것
    /// — 경계 설정 변경 시 재해석이 달라진다. 저장 값은 logicalDay(ofStored:)로 해석한다.
    func logicalDate(of date: Date) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(-boundaryOffset))
    }

    /// 저장된 날짜 키(scheduledDate/dueDate)가 가리키는 논리적 날짜.
    /// 경계 오프셋을 다시 적용하지 않으므로 경계 설정을 바꿔도 기존 태스크의 소속 날짜가 유지된다.
    /// 과거 규약 값(자정 + 저장 당시 오프셋, 오프셋 < 24h)도 같은 날짜로 해석돼 마이그레이션이 필요 없다.
    func logicalDay(ofStored stored: Date) -> Date {
        calendar.startOfDay(for: stored)
    }

    func logicalToday() -> Date {
        logicalDate(of: now())
    }

    func logicalYesterday() -> Date {
        calendar.date(byAdding: .day, value: -1, to: logicalToday())!
    }

    /// 논리적 날짜 day의 하루가 실제로 시작되는 시각 (day 자정 + 기준 시각 오프셋).
    /// 타이머/경계 계산용 실제 시각이다 — scheduledDate 저장 값으로 쓰지 말 것(scheduledDateValue 사용).
    func startOfLogicalDay(_ day: Date) -> Date {
        calendar.startOfDay(for: day).addingTimeInterval(boundaryOffset)
    }

    /// scheduledDate 저장 규약(단일 소스): 논리적 날짜 day에 배정하는 태스크의 scheduledDate는
    /// 항상 그 날짜의 자정 Date(경계와 무관한 날짜 키)로 저장한다. 모든 쓰기 경로는 이 헬퍼를 거치고,
    /// 읽기는 logicalDay(ofStored:)로만 해석할 것 — 경계 오프셋이 저장 값에 섞이면
    /// 경계 설정 변경 시 소속 날짜가 밀리는 버그가 재발한다 (회귀 테스트 있음).
    func scheduledDateValue(for day: Date) -> Date {
        calendar.startOfDay(for: day)
    }

    /// 오늘(논리적)에 배정할 때 저장하는 scheduledDate 값
    func scheduledToday() -> Date {
        scheduledDateValue(for: logicalToday())
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

    // MARK: - 논리적 주 (v11 §20.1)
    // 논리적 주 = 주 시작 요일(설정, 기본 월)의 기준 시각에 시작한다. 예: 월 06:00 경계면
    // 월요일 05:59는 아직 이전 주, 06:00부터 새 주. "주 키"는 그 주가 시작하는 달력 날짜의
    // 자정 Date — scheduledDate와 같은 '자정 날짜 키' 규약이라 경계 설정을 바꿔도 소속이 안 밀린다.

    /// 저장된 날짜 키(자정 정규화 권장)가 속한 논리적 주의 시작 날짜 키.
    /// 타임스탬프에는 쓰지 말 것 — 실제 시각은 logicalWeekStart(of:)로 해석한다.
    func weekStart(ofDay day: Date) -> Date {
        let normalized = calendar.startOfDay(for: day)
        let weekday = calendar.component(.weekday, from: normalized)
        let offset = (weekday - settings.weekStartDay + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: normalized)!
    }

    /// 주어진 실제 시각(타임스탬프)이 속한 논리적 주의 시작 날짜 키(자정 정규화).
    /// 하루 소속(logicalDate)을 먼저 판정하므로 주 시작 요일의 기준 시각 전은 이전 주에 속한다.
    func logicalWeekStart(of date: Date) -> Date {
        weekStart(ofDay: logicalDate(of: date))
    }

    /// 현재 논리적 주의 시작 날짜 키
    func currentWeekStart() -> Date {
        logicalWeekStart(of: now())
    }

    /// weekStart 기준 이전 주의 시작 날짜 키
    func previousWeekStart(before weekStart: Date) -> Date {
        calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: weekStart))!
    }

    /// weekStart 기준 다음 주의 시작 날짜 키
    func nextWeekStart(after weekStart: Date) -> Date {
        calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: weekStart))!
    }

    /// 두 실제 시각이 같은 논리적 주에 속하는가
    func isSameLogicalWeek(_ a: Date, _ b: Date) -> Bool {
        logicalWeekStart(of: a) == logicalWeekStart(of: b)
    }

    /// D-day: due 날짜 키의 날짜 - 기준 시각(타임스탬프)의 논리적 날짜 (일 단위). 0=오늘, 음수=지남.
    /// dueDate는 저장된 날짜 키이므로 경계 오프셋으로 재해석하지 않는다.
    func dDay(of dueDate: Date, from reference: Date? = nil) -> Int {
        let ref = reference ?? now()
        let from = logicalDate(of: ref)
        let to = logicalDay(ofStored: dueDate)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}
