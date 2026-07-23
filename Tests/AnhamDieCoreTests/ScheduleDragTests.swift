import Foundation
import Testing
@testable import AnhamDieApp

// PLAN §12.6 — 날짜 간 이동: 같은 그룹 = reorder, 다른 날짜 그룹 = reschedule.

@MainActor
@Suite("ScheduleDrag 날짜 간 이동 규칙")
struct ScheduleDragTests {
    private let store: JSONTaskStore
    private let boundary: DayBoundaryService

    private let today = midnight(2026, 7, 22)
    private let yesterday = midnight(2026, 7, 21)
    private let tomorrow = midnight(2026, 7, 23)
    private let day28 = midnight(2026, 7, 28)

    init() {
        store = makeTempStore()
        boundary = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
    }

    @Test("같은 그룹 판정 = reorder")
    func sameGroupIsReorder() {
        #expect(ScheduleDrag.action(from: .today, to: .today, boundary: boundary) == .reorder)
        #expect(ScheduleDrag.action(from: .upcoming(day28), to: .upcoming(day28), boundary: boundary) == .reorder)
        #expect(ScheduleDrag.action(from: .past, to: .past, boundary: boundary) == .reorder)
    }

    @Test("다른 날짜 그룹 = reschedule, 대상 그룹의 자정 날짜 키로")
    func differentGroupReschedules() {
        #expect(ScheduleDrag.action(from: .past, to: .today, boundary: boundary)
            == .reschedule(to: boundary.scheduledToday()))
        #expect(ScheduleDrag.action(from: .today, to: .upcoming(day28), boundary: boundary)
            == .reschedule(to: boundary.scheduledDateValue(for: day28)))
        #expect(ScheduleDrag.action(from: .upcoming(tomorrow), to: .today, boundary: boundary)
            == .reschedule(to: boundary.scheduledToday()))
    }

    @Test("past로의 드롭은 날짜가 없어 reorder로 처리")
    func dropToPastIsReorder() {
        #expect(ScheduleDrag.action(from: .today, to: .past, boundary: boundary) == .reorder)
    }

    @Test("reschedule 날짜는 자정 날짜 키 규약을 따른다")
    func rescheduleDateIsMidnightKey() {
        #expect(ScheduleDrag.rescheduleDate(for: .today, boundary: boundary) == today)
        #expect(ScheduleDrag.rescheduleDate(for: .upcoming(day28), boundary: boundary) == day28)
        #expect(ScheduleDrag.rescheduleDate(for: .past, boundary: boundary) == nil)
    }

    @Test("apply: reschedule이면 scheduledDate 변경 + 저장, 판정 반환")
    func applyReschedule() {
        let task = TodoTask(title: "지난", scheduledDate: yesterday)
        store.addTask(task)
        let result = ScheduleDrag.apply(
            dragged: task, from: .past, to: .today, store: store, boundary: boundary
        )
        #expect(result == .reschedule(to: today))
        #expect(task.scheduledDate == today)
    }

    @Test("apply: reorder면 scheduledDate 불변")
    func applyReorderKeepsDate() {
        let task = TodoTask(title: "오늘", scheduledDate: today)
        store.addTask(task)
        let result = ScheduleDrag.apply(
            dragged: task, from: .today, to: .today, store: store, boundary: boundary
        )
        #expect(result == .reorder)
        #expect(task.scheduledDate == today)
    }

    @Test("scheduleGroup: 태스크의 현재 그룹을 섹션 배치와 일치하게 판정")
    func scheduleGroupClassification() {
        let past = TodoTask(title: "지난", scheduledDate: yesterday)
        let todayTask = TodoTask(title: "오늘", scheduledDate: today)
        let future = TodoTask(title: "예정", scheduledDate: day28)
        let backlog = TodoTask(title: "백로그")
        store.addTask(past)
        store.addTask(todayTask)
        store.addTask(future)
        store.addTask(backlog)

        #expect(store.scheduleGroup(of: past, boundary: boundary) == .past)
        #expect(store.scheduleGroup(of: todayTask, boundary: boundary) == .today)
        #expect(store.scheduleGroup(of: future, boundary: boundary) == .upcoming(day28))
        #expect(store.scheduleGroup(of: backlog, boundary: boundary) == nil)
    }

    @Test("scheduleGroup: 어제 scheduled + 오늘 due는 .today (섹션 규약 승계)")
    func scheduleGroupHonorsTodayPrecedence() {
        let task = TodoTask(title: "혼합", scheduledDate: yesterday, dueDate: today)
        store.addTask(task)
        #expect(store.scheduleGroup(of: task, boundary: boundary) == .today)
    }
}
