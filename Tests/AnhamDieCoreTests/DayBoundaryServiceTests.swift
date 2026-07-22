import Foundation
import Testing
@testable import AnhamDieApp

@Suite("DayBoundaryService")
struct DayBoundaryServiceTests {
    private func makeService(hour: Int = 9, minute: Int = 0, now: Date) -> DayBoundaryService {
        DayBoundaryService(settings: makeTestSettings(boundaryHour: hour, boundaryMinute: minute), now: { now })
    }

    @Test("기준 시각 이전은 전날의 논리적 하루")
    func beforeBoundaryIsPreviousDay() {
        let service = makeService(now: date(2026, 7, 22, 8, 59))
        #expect(service.logicalToday() == midnight(2026, 7, 21))
    }

    @Test("기준 시각 정각부터 새 하루")
    func atBoundaryIsNewDay() {
        let service = makeService(now: date(2026, 7, 22, 9, 0))
        #expect(service.logicalToday() == midnight(2026, 7, 22))
    }

    @Test("자정 직후 새벽은 여전히 전날")
    func afterMidnightStillPreviousDay() {
        let service = makeService(now: date(2026, 7, 23, 2, 30))
        #expect(service.logicalToday() == midnight(2026, 7, 22))
    }

    @Test("기준 시각 00:00이면 달력 날짜와 동일")
    func midnightBoundaryMatchesCalendarDay() {
        let service = makeService(hour: 0, now: date(2026, 7, 23, 0, 30))
        #expect(service.logicalToday() == midnight(2026, 7, 23))
    }

    @Test("기준 시각 분 단위 설정 반영")
    func boundaryMinuteRespected() {
        let service = makeService(hour: 9, minute: 30, now: date(2026, 7, 22, 9, 15))
        #expect(service.logicalToday() == midnight(2026, 7, 21))
    }

    @Test("logicalYesterday는 논리적 오늘의 하루 전")
    func logicalYesterday() {
        let service = makeService(now: date(2026, 7, 22, 10, 0))
        #expect(service.logicalYesterday() == midnight(2026, 7, 21))
    }

    @Test("nextBoundaryDate — 기준 시각 이후엔 내일 기준 시각")
    func nextBoundaryAfterBoundary() {
        let service = makeService(now: date(2026, 7, 22, 10, 0))
        #expect(service.nextBoundaryDate() == date(2026, 7, 23, 9, 0))
    }

    @Test("nextBoundaryDate — 기준 시각 이전엔 오늘 기준 시각")
    func nextBoundaryBeforeBoundary() {
        let service = makeService(now: date(2026, 7, 22, 8, 0))
        #expect(service.nextBoundaryDate() == date(2026, 7, 22, 9, 0))
    }

    @Test("startOfLogicalDay는 자정 + 오프셋")
    func startOfLogicalDay() {
        let service = makeService(now: date(2026, 7, 22, 10, 0))
        #expect(service.startOfLogicalDay(midnight(2026, 7, 22)) == date(2026, 7, 22, 9, 0))
    }

    @Test("isSameLogicalDay — 새벽과 전날 오후는 같은 하루")
    func sameLogicalDayAcrossMidnight() {
        let service = makeService(now: date(2026, 7, 22, 10, 0))
        #expect(service.isSameLogicalDay(date(2026, 7, 22, 15, 0), date(2026, 7, 23, 2, 0)))
        #expect(!service.isSameLogicalDay(date(2026, 7, 22, 15, 0), date(2026, 7, 23, 10, 0)))
    }

    @Test("D-day 계산")
    func dDay() {
        let service = makeService(now: date(2026, 7, 22, 10, 0))
        #expect(service.dDay(of: date(2026, 7, 25, 12, 0)) == 3)
        #expect(service.dDay(of: date(2026, 7, 22, 12, 0)) == 0)
        #expect(service.dDay(of: date(2026, 7, 20, 12, 0)) == -2)
    }
}
