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
    private let day30 = midnight(2026, 7, 30)

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

    @Test("scheduled/due가 서로 다른 두 미래 날짜면 예정에 한 번만, 가장 이른 날짜에 (id 유일성)")
    func distinctFutureScheduledAndDueDedup() {
        // scheduled=7/28, due=7/30 — scheduleSections는 두 날짜 그룹 모두에 넣지만
        // 예정 평탄화는 가장 이른 날짜(7/28)에만 한 번 넣어야 한다(§12.4 단일 ForEach id 유일성).
        let spanning = TodoTask(title: "걸침", scheduledDate: day28, dueDate: day30)
        store.addTask(spanning)

        let up = sections().upcoming
        #expect(up.count == 1)
        #expect(Set(up.map { $0.task.id }).count == 1)
        #expect(up[0].task.id == spanning.id)
        #expect(up[0].day == day28)
        #expect(up[0].isGroupStart == true)
        #expect(up[0].dividerLabel == "7/28 (화)")
        // 표시 위치(가장 이른 날짜)와 드래그 소스 그룹 판정이 일치해야 한다.
        #expect(store.scheduleGroup(of: spanning, boundary: boundary) == .upcoming(day28))
    }

    @Test("걸친 태스크의 늦은 날짜에 고유 태스크가 있으면 그 날짜 구분선은 다음 고유 항목이 잇는다")
    func spanningTaskDoesNotStealLaterDivider() {
        // A: scheduled=7/28, due=7/30 (걸침). B: 7/30 고유. 7/30 그룹의 첫 태스크는 A(중복)라도
        // A는 이미 7/28에서 소비됐으므로 7/30 구분선은 B가 이어받아야 한다(빈 구분선/누락 없음).
        let a = TodoTask(title: "걸침", scheduledDate: day28, dueDate: day30, priority: .high)
        let b = TodoTask(title: "30일고유", scheduledDate: day30, priority: .low)
        store.addTask(a)
        store.addTask(b)

        let up = sections().upcoming
        #expect(up.map { $0.task.id } == [a.id, b.id])
        #expect(Set(up.map { $0.task.id }).count == up.count) // id 유일
        #expect(up[0].day == day28)
        #expect(up[0].dividerLabel == "7/28 (화)")
        #expect(up[1].day == day30)
        #expect(up[1].isGroupStart == true)
        #expect(up[1].dividerLabel == "7/30 (목)")
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

    // 회귀 방지 (cross-bucket): scheduled∪due 소속(§10.1)으로 한 태스크가 오늘+미래 두 그룹에
    // 걸치면 today/upcoming 형제 ForEach에 같은 task.id가 나뉘어 들어가 SwiftUI가 깨진다.
    // 가장 이른 그룹(오늘)에만 두어야 한다. (두 미래 날짜 케이스는 위 dedup 테스트에서 검증.)

    @Test("오늘 scheduled + 미래 due는 오늘에만 (예정에 중복 안 뜸)")
    func todayScheduledFutureDueOnlyInToday() {
        let t = TodoTask(title: "오늘시작 30일마감", scheduledDate: today, dueDate: day30)
        store.addTask(t)

        let s = sections()
        #expect(s.today.map { $0.id } == [t.id])
        #expect(s.upcoming.isEmpty)                     // today/upcoming 형제 ForEach 간 id 중복 방지
    }

    @Test("미래 scheduled + 오늘 due도 오늘에만 (예정에 중복 안 뜸)")
    func futureScheduledTodayDueOnlyInToday() {
        let t = TodoTask(title: "30일예정 오늘마감", scheduledDate: day30, dueDate: today)
        store.addTask(t)

        let s = sections()
        #expect(s.today.map { $0.id } == [t.id])
        #expect(s.upcoming.isEmpty)
    }
}
