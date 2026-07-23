import Foundation
import Testing
@testable import AnhamDieApp

// PLAN §12.4 — "해야할 일" 3섹션(지난·오늘·예정) + 예정 평탄화·미니 구분선.

@MainActor
@Suite("todoSectionsV4 3섹션·예정 평탄화")
struct UpcomingScheduleTests {
    private let store: JSONTaskStore
    private let boundary: DayBoundaryService

    // 논리적 오늘 = 2026-07-22 (경계 09:00, 현재 10:00)
    private let today = midnight(2026, 7, 22)
    private let yesterday = midnight(2026, 7, 21)
    private let tomorrow = midnight(2026, 7, 23)
    private let day28 = midnight(2026, 7, 28)

    init() {
        store = makeTempStore()
        boundary = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
    }

    private func sections() -> TodoSectionsV4 {
        store.todoSectionsV4(boundary: boundary)
    }

    @Test("빈 스토어: 3섹션 모두 비어 있음")
    func emptyStore() {
        let s = sections()
        #expect(s.past.isEmpty)
        #expect(s.today.isEmpty)
        #expect(s.upcoming.isEmpty)
    }

    @Test("지난·오늘·예정으로 정확히 분배된다")
    func distributesIntoThreeSections() {
        let past = TodoTask(title: "지난", scheduledDate: yesterday)
        let todayTask = TodoTask(title: "오늘", scheduledDate: today)
        let tomorrowTask = TodoTask(title: "내일", scheduledDate: tomorrow)
        store.addTask(past)
        store.addTask(todayTask)
        store.addTask(tomorrowTask)

        let s = sections()
        #expect(s.past.map { $0.id } == [past.id])
        #expect(s.today.map { $0.id } == [todayTask.id])
        #expect(s.upcoming.map { $0.task.id } == [tomorrowTask.id])
    }

    @Test("예정 첫 항목(내일)에 '내일 M/d' 구분선, 그룹 시작 플래그")
    func tomorrowDividerLabel() {
        store.addTask(TodoTask(title: "내일 것", scheduledDate: tomorrow))
        let item = sections().upcoming.first
        #expect(item?.isGroupStart == true)
        #expect(item?.dividerLabel == "내일 7/23")
        #expect(item?.day == tomorrow)
    }

    @Test("여러 날짜 그룹: 각 그룹 첫 항목만 isGroupStart·라벨, 나머지는 nil")
    func groupBoundaryFlags() {
        let a = TodoTask(title: "내일1", scheduledDate: tomorrow, priority: .high)
        let b = TodoTask(title: "내일2", scheduledDate: tomorrow, priority: .low)
        let c = TodoTask(title: "28일", scheduledDate: day28)
        store.addTask(a)
        store.addTask(b)
        store.addTask(c)

        let up = sections().upcoming
        // 내일(a 우선순위 높음 → 먼저), 내일(b), 28일(c)
        #expect(up.map { $0.task.id } == [a.id, b.id, c.id])
        #expect(up[0].isGroupStart == true)
        #expect(up[0].dividerLabel == "내일 7/23")
        #expect(up[1].isGroupStart == false)
        #expect(up[1].dividerLabel == nil)
        #expect(up[2].isGroupStart == true)
        #expect(up[2].dividerLabel == "7/28 (화)")
    }

    @Test("빈 내일 그룹은 예정 시퀀스에 구분선을 만들지 않는다")
    func emptyTomorrowNoDivider() {
        // 28일만 있고 내일은 비어 있음
        store.addTask(TodoTask(title: "28일", scheduledDate: day28))
        let up = sections().upcoming
        #expect(up.count == 1)
        #expect(up[0].day == day28)
        #expect(up[0].dividerLabel == "7/28 (화)")
    }

    @Test("편의 접근자 pastSection/todaySection/upcomingItems가 통합 결과와 일치")
    func convenienceAccessors() {
        let past = TodoTask(title: "지난", scheduledDate: yesterday)
        let todayTask = TodoTask(title: "오늘", scheduledDate: today)
        let future = TodoTask(title: "예정", scheduledDate: day28)
        store.addTask(past)
        store.addTask(todayTask)
        store.addTask(future)

        #expect(store.pastSection(boundary: boundary).map { $0.id } == [past.id])
        #expect(store.todaySection(boundary: boundary).map { $0.id } == [todayTask.id])
        #expect(store.upcomingItems(boundary: boundary).map { $0.task.id } == [future.id])
    }

    @Test("백로그·오늘 완료는 v1 규약 그대로 승계 (지난에 안 뜸, 오늘에 뜸)")
    func inheritsScheduleSectionRules() {
        store.addTask(TodoTask(title: "백로그"))
        let doneToday = TodoTask(title: "오늘완료", scheduledDate: today)
        doneToday.markCompleted(at: date(2026, 7, 22, 9, 30))
        store.addTask(doneToday)

        let s = sections()
        #expect(s.past.isEmpty)
        #expect(s.today.map { $0.id } == [doneToday.id])
        #expect(s.upcoming.isEmpty)
    }
}
