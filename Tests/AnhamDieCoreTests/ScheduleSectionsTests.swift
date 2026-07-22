import Foundation
import Testing
@testable import AnhamDieApp

// MARK: - "해야할 일" 날짜 그룹핑 (PLAN §10.1 scheduleSections)

@MainActor
@Suite("scheduleSections 날짜 그룹")
struct ScheduleSectionsTests {
    private let store: JSONTaskStore
    private let boundary: DayBoundaryService

    // 논리적 오늘 = 2026-07-22 (경계 09:00, 현재 시각 10:00)
    private let today = midnight(2026, 7, 22)
    private let yesterday = midnight(2026, 7, 21)
    private let tomorrow = midnight(2026, 7, 23)

    init() {
        store = makeTempStore()
        boundary = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
    }

    private func sections(tagFilter: TaskTag? = nil) -> [(day: Date?, tasks: [TodoTask])] {
        store.scheduleSections(boundary: boundary, tagFilter: tagFilter)
    }

    @Test("빈 스토어: 오늘·내일 섹션은 항상 존재, 지난 할 일 섹션은 없음")
    func emptyStoreHasTodayAndTomorrow() {
        let result = sections()
        #expect(result.map { $0.day } == [today, tomorrow])
        #expect(result.allSatisfy { $0.tasks.isEmpty })
    }

    @Test("어제 scheduled 미완료 → 지난 할 일(day=nil) 첫 섹션")
    func yesterdayScheduledGoesToPast() {
        let task = TodoTask(title: "어제 것", scheduledDate: yesterday)
        store.addTask(task)
        let result = sections()
        #expect(result.first?.day == nil)
        #expect(result.first?.tasks.map { $0.id } == [task.id])
    }

    @Test("due 지난 미완료(overdue)도 지난 할 일에 통합된다")
    func overdueGoesToPast() {
        let task = TodoTask(title: "overdue", dueDate: midnight(2026, 7, 20))
        store.addTask(task)
        let result = sections()
        #expect(result.first?.day == nil)
        #expect(result.first?.tasks.map { $0.id } == [task.id])
    }

    @Test("어제 scheduled + 오늘 due는 지난이 아니라 오늘 섹션에만 나타난다 (중복 없음)")
    func pastScheduledDueTodayAppearsOnlyToday() {
        let task = TodoTask(title: "오늘 due", scheduledDate: yesterday, dueDate: today)
        store.addTask(task)
        let result = sections()
        #expect(result.first?.day == today)
        let todaySection = result.first { $0.day == today }
        #expect(todaySection?.tasks.map { $0.id } == [task.id])
        #expect(result.flatMap { $0.tasks }.count == 1)
    }

    @Test("오늘·내일·이후 날짜 오름차순 배치, 빈 이후 날짜는 생략")
    func futureDaysAscending() {
        let t0 = TodoTask(title: "오늘", scheduledDate: today)
        let t1 = TodoTask(title: "내일", scheduledDate: tomorrow)
        let t3 = TodoTask(title: "사흘 뒤 due", dueDate: midnight(2026, 7, 25))
        store.addTask(t3)
        store.addTask(t1)
        store.addTask(t0)
        let result = sections()
        #expect(result.map { $0.day } == [today, tomorrow, midnight(2026, 7, 25)])
        #expect(result[0].tasks.map { $0.id } == [t0.id])
        #expect(result[1].tasks.map { $0.id } == [t1.id])
        #expect(result[2].tasks.map { $0.id } == [t3.id])
    }

    @Test("백로그(scheduled·due 모두 nil)는 제외된다")
    func backlogExcluded() {
        store.addTask(TodoTask(title: "백로그"))
        let result = sections()
        #expect(result.flatMap { $0.tasks }.isEmpty)
    }

    @Test("취소 태스크는 제외, 오늘 완료 태스크는 오늘 섹션에 포함 (v1 tasks(on:) 규약)")
    func statusRules() {
        let cancelled = TodoTask(title: "취소", scheduledDate: today)
        cancelled.markCancelled(at: date(2026, 7, 22, 9, 30))
        let doneToday = TodoTask(title: "완료", scheduledDate: today)
        doneToday.markCompleted(at: date(2026, 7, 22, 9, 30))
        store.addTask(cancelled)
        store.addTask(doneToday)
        let result = sections()
        let todaySection = result.first { $0.day == today }
        #expect(todaySection?.tasks.map { $0.id } == [doneToday.id])
    }

    @Test("어제 완료된 태스크는 지난 할 일에 나타나지 않는다 (히스토리 소관)")
    func completedYesterdayNotInPast() {
        let task = TodoTask(title: "어제 완료", scheduledDate: yesterday)
        task.markCompleted(at: date(2026, 7, 21, 15, 0))
        store.addTask(task)
        let result = sections()
        #expect(result.first?.day == today)
        #expect(result.flatMap { $0.tasks }.isEmpty)
    }

    @Test("지난 할 일은 놓친 날짜 오름차순으로 정렬된다")
    func pastSortedByMissedDay() {
        let older = TodoTask(title: "그저께", scheduledDate: midnight(2026, 7, 20))
        let newer = TodoTask(title: "어제", scheduledDate: yesterday)
        store.addTask(newer)
        store.addTask(older)
        let result = sections()
        #expect(result.first?.tasks.map { $0.id } == [older.id, newer.id])
    }

    @Test("tagFilter: 해당 태그가 붙은 태스크만 남는다")
    func tagFilterApplies() {
        let tag = TaskTag(name: "업무")
        store.addTag(tag)
        let tagged = TodoTask(title: "태그 있음", scheduledDate: today, tagIDs: [tag.id])
        let untaggedToday = TodoTask(title: "태그 없음", scheduledDate: today)
        let untaggedPast = TodoTask(title: "태그 없는 과거", scheduledDate: yesterday)
        store.addTask(tagged)
        store.addTask(untaggedToday)
        store.addTask(untaggedPast)
        let result = sections(tagFilter: tag)
        #expect(result.map { $0.day } == [today, tomorrow])
        #expect(result.flatMap { $0.tasks }.map { $0.id } == [tagged.id])
    }
}

// MARK: - lastUsedDueDate 영속화 (PLAN §10.7)

@MainActor
@Suite("lastUsedDueDate 설정")
struct LastUsedDueDateTests {
    @Test("설정 후 같은 defaults로 재생성하면 복원된다")
    func roundTrips() {
        let suite = "AnhamDieTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let settings = AppSettings(defaults: defaults)
        #expect(settings.lastUsedDueDate == nil)
        let day = midnight(2026, 7, 25)
        settings.lastUsedDueDate = day

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.lastUsedDueDate == day)

        reloaded.lastUsedDueDate = nil
        let cleared = AppSettings(defaults: defaults)
        #expect(cleared.lastUsedDueDate == nil)
    }
}
