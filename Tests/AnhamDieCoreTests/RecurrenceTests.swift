import Foundation
import Testing
@testable import AnhamDieApp

// PLAN §11.5 — 반복 규칙·다음 발생 생성·중복 방지·스키마 마이그레이션.
// 2026-07-24 = 금요일, 07-25 = 토요일, 07-27 = 월요일.

@Suite("반복 규칙 계산")
struct RecurrenceRuleTests {
    let cal = Calendar.current

    @Test("매일: 다음 날")
    func daily() {
        let next = RecurrenceRule.daily.nextOccurrence(after: midnight(2026, 7, 23), calendar: cal)
        #expect(next == midnight(2026, 7, 24))
    }

    @Test("평일: 금요일 다음은 월요일")
    func weekdaysSkipsWeekend() {
        let next = RecurrenceRule.weekdays.nextOccurrence(after: midnight(2026, 7, 24), calendar: cal)
        #expect(next == midnight(2026, 7, 27))
    }

    @Test("평일: 토요일 기준도 월요일")
    func weekdaysFromSaturday() {
        let next = RecurrenceRule.weekdays.nextOccurrence(after: midnight(2026, 7, 25), calendar: cal)
        #expect(next == midnight(2026, 7, 27))
    }

    @Test("매주: 같은 요일이면 +7일 (주 경계)")
    func weeklySameDayWrapsWeek() {
        // 7/23은 목요일(weekday 5)
        let next = RecurrenceRule.weekly([5]).nextOccurrence(after: midnight(2026, 7, 23), calendar: cal)
        #expect(next == midnight(2026, 7, 30))
    }

    @Test("매주 복수 요일: 가장 가까운 다음 요일")
    func weeklyMultipleDays() {
        // 목(7/23) 기준, 월(2)·금(6) 중 가까운 것은 금(7/24)
        let next = RecurrenceRule.weekly([2, 6]).nextOccurrence(after: midnight(2026, 7, 23), calendar: cal)
        #expect(next == midnight(2026, 7, 24))
    }

    @Test("none·빈 weekly는 다음 발생 없음")
    func noneAndEmptyWeekly() {
        #expect(RecurrenceRule.none.nextOccurrence(after: midnight(2026, 7, 23), calendar: cal) == nil)
        #expect(RecurrenceRule.weekly([]).nextOccurrence(after: midnight(2026, 7, 23), calendar: cal) == nil)
    }

    @Test("Codable 왕복 (weekly 요일 집합 보존)")
    func codableRoundtrip() throws {
        for rule: RecurrenceRule in [.none, .daily, .weekdays, .weekly([2, 4, 6])] {
            let data = try JSONEncoder().encode(rule)
            let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
            #expect(decoded == rule)
        }
    }
}

@MainActor
@Suite("반복 발생 생성 (RecurrenceService)")
struct RecurrenceServiceTests {
    // 2026-07-23(목) 14:00 고정
    func makeEnv() -> (JSONTaskStore, DayBoundaryService, RecurrenceService) {
        let settings = makeTestSettings()
        let store = makeTempStore()
        let boundary = DayBoundaryService(settings: settings, now: { date(2026, 7, 23, 14) })
        return (store, boundary, RecurrenceService(store: store, dayBoundary: boundary))
    }

    @Test("완료 시 다음 발생 생성: 제목·태그·우선순위·규칙 승계, 서브태스크 미완료 복제")
    func nextOccurrenceInherits() {
        let (store, boundary, service) = makeEnv()
        let tag = TaskTag(name: "운동")
        store.addTag(tag)
        let task = TodoTask(
            title: "달리기", note: "5km",
            scheduledDate: boundary.scheduledToday(),
            priority: .high, tagIDs: [tag.id],
            subtasks: [Subtask(title: "스트레칭", isDone: true)],
            recurrence: .daily
        )
        store.addTaskApplyingInitialOrder(task)
        task.markCompleted(at: boundary.now())

        let next = service.scheduleNextOccurrence(after: task)
        #expect(next != nil)
        #expect(next?.title == "달리기")
        #expect(next?.note == "5km")
        #expect(next?.priority == .high)
        #expect(next?.tagIDs == [tag.id])
        #expect(next?.recurrence == .daily)
        #expect(next?.rolloverCount == 0)
        #expect(next?.subtasks.count == 1)
        #expect(next?.subtasks.first?.isDone == false)
        #expect(next?.subtasks.first?.id != task.subtasks.first?.id)
        #expect(next?.scheduledDate.map { boundary.logicalDay(ofStored: $0) } == midnight(2026, 7, 24))
        // 시리즈ID(중복 방지 키)가 원본·다음 발생 양쪽에 부여된다
        #expect(task.recurrenceSeriesID == task.id)
        #expect(next?.recurrenceSeriesID == task.id)
    }

    @Test("중복 생성 방지: 같은 발생 날짜로 두 번 생성되지 않는다")
    func duplicatePrevention() {
        let (store, boundary, service) = makeEnv()
        let task = TodoTask(title: "매일", scheduledDate: boundary.scheduledToday(), recurrence: .daily)
        store.addTaskApplyingInitialOrder(task)
        task.markCompleted(at: boundary.now())

        #expect(service.scheduleNextOccurrence(after: task) != nil)
        #expect(service.scheduleNextOccurrence(after: task) == nil)
        #expect(store.tasks.count == 2)
    }

    @Test("지난 회차를 늦게 정리해도 다음 발생은 오늘 이후")
    func overdueBaseUsesToday() {
        let (store, boundary, service) = makeEnv()
        // 3일 전(7/20 월) 예정이었던 매일 반복
        let task = TodoTask(
            title: "밀린 반복",
            scheduledDate: boundary.scheduledDateValue(for: midnight(2026, 7, 20)),
            recurrence: .daily
        )
        store.addTaskApplyingInitialOrder(task)
        task.markCompleted(at: boundary.now())

        let next = service.scheduleNextOccurrence(after: task)
        #expect(next?.scheduledDate.map { boundary.logicalDay(ofStored: $0) } == midnight(2026, 7, 24))
    }

    @Test("버리기(취소)로도 다음 회차 생성 — RolloverService.cancel 경유")
    func cancelGeneratesNext() {
        let settings = makeTestSettings()
        let store = makeTempStore()
        let boundary = DayBoundaryService(settings: settings, now: { date(2026, 7, 23, 14) })
        let rollover = RolloverService(store: store, dayBoundary: boundary)
        // 어제(7/22) 예정 매일 반복 — 이월 제안에서 '버리기'
        let task = TodoTask(
            title: "버려질 반복",
            scheduledDate: boundary.scheduledDateValue(for: midnight(2026, 7, 22)),
            recurrence: .daily
        )
        store.addTaskApplyingInitialOrder(task)

        rollover.cancel(task)
        #expect(task.status == .cancelled)
        let next = store.tasks.first { $0.id != task.id }
        #expect(next?.status == .active)
        #expect(next?.scheduledDate.map { boundary.logicalDay(ofStored: $0) } == midnight(2026, 7, 24))
    }

    @Test("반복 없는 task는 생성하지 않는다")
    func noneRuleNoop() {
        let (store, boundary, service) = makeEnv()
        let task = TodoTask(title: "일반", scheduledDate: boundary.scheduledToday())
        store.addTaskApplyingInitialOrder(task)
        task.markCompleted(at: boundary.now())
        #expect(service.scheduleNextOccurrence(after: task) == nil)
        #expect(store.tasks.count == 1)
    }

    @Test("구버전(v1) 문서 로드: recurrence 없는 태스크는 .none으로 마이그레이션")
    func v1DocumentLoadsWithoutRecurrence() throws {
        let dir = makeTempStoreDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let v1JSON = """
        {"version":1,"tags":[],"tasks":[{
            "id":"11111111-1111-1111-1111-111111111111",
            "title":"구버전","note":"","createdAt":"2026-07-20T01:00:00Z",
            "status":"active","priority":1,"rolloverCount":0,"sortOrder":5,
            "tagIDs":[],"subtasks":[]
        }]}
        """
        try v1JSON.write(to: dir.appendingPathComponent("store.json"), atomically: true, encoding: .utf8)

        let store = JSONTaskStore(directory: dir)
        #expect(store.tasks.count == 1)
        #expect(store.tasks.first?.recurrence == RecurrenceRule.none)
        #expect(store.tasks.first?.recurrenceSeriesID == nil)
        // 마이그레이션이 sortOrder를 재부여하고 v2로 저장한다
        #expect(store.tasks.first?.sortOrder == 0)
        let saved = try String(contentsOf: dir.appendingPathComponent("store.json"), encoding: .utf8)
        #expect(saved.contains("\"version\" : 2"))
    }
}
