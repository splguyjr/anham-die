import Foundation
import Testing
@testable import AnhamDieApp

@MainActor
@Suite("RolloverService")
struct RolloverServiceTests {
    private let store: JSONTaskStore
    private let boundary: DayBoundaryService
    private let rollover: RolloverService

    init() {
        store = makeTempStore()
        boundary = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
        rollover = RolloverService(store: store, dayBoundary: boundary)
    }

    @Test("이전 하루의 미완료만 조회된다")
    func unfinishedFromPreviousDays() {
        let yesterdayActive = TodoTask(title: "어제 미완료", scheduledDate: date(2026, 7, 21, 10, 0))
        let yesterdayDone = TodoTask(title: "어제 완료", scheduledDate: date(2026, 7, 21, 10, 0))
        yesterdayDone.markCompleted(at: date(2026, 7, 21, 18, 0))
        let todayActive = TodoTask(title: "오늘", scheduledDate: date(2026, 7, 22, 9, 30))
        // 달력상 오늘 새벽 2시에 작성 → 쓰기 경로(scheduledToday())가 논리적 어제(7/21) 키로 저장한다
        let earlyBoundary = DayBoundaryService(
            settings: makeTestSettings(), now: { date(2026, 7, 22, 2, 0) })
        let earlyMorning = TodoTask(title: "새벽 작성", scheduledDate: earlyBoundary.scheduledToday())
        let backlog = TodoTask(title: "백로그")
        [yesterdayActive, yesterdayDone, todayActive, earlyMorning, backlog].forEach(store.addTask)

        let unfinishedIDs = Set(rollover.unfinishedTasksFromPreviousDays().map(\.id))
        let expectedIDs = Set([yesterdayActive.id, earlyMorning.id])
        #expect(unfinishedIDs == expectedIDs)
    }

    @Test("오늘로 이월 시 rolloverCount 증가")
    func rolloverIncrementsCount() {
        let task = TodoTask(title: "이월 대상", scheduledDate: date(2026, 7, 21, 10, 0))
        store.addTask(task)

        rollover.rolloverToToday(task)
        #expect(task.rolloverCount == 1)
        #expect(boundary.logicalDay(ofStored: task.scheduledDate!) == midnight(2026, 7, 22))
        #expect(rollover.unfinishedTasksFromPreviousDays().isEmpty)

        rollover.rolloverToToday(task)
        #expect(task.rolloverCount == 2)
    }

    @Test("보류는 백로그로 이동")
    func moveToBacklog() {
        let task = TodoTask(title: "보류 대상", scheduledDate: date(2026, 7, 21, 10, 0))
        store.addTask(task)

        rollover.moveToBacklog(task)
        #expect(task.scheduledDate == nil)
        #expect(task.isActive)
        #expect(store.backlogTasks().map(\.id) == [task.id])
        #expect(rollover.unfinishedTasksFromPreviousDays().isEmpty)
    }

    @Test("백로그로 보내면 이월 카운트가 0으로 리셋된다 (§13.3)")
    func backlogResetsRolloverCount() {
        let task = TodoTask(title: "이월 이력 있음", scheduledDate: date(2026, 7, 21, 10, 0), rolloverCount: 3)
        store.addTask(task)

        rollover.moveToBacklog(task)
        #expect(task.scheduledDate == nil)
        #expect(task.rolloverCount == 0)
    }

    @Test("백로그 왕복 후 오늘로 가져와도 이월 카운트 0 (백로그 항목엔 ↺ 없음)")
    func backlogRoundTripHasNoRolloverBadge() {
        let task = TodoTask(title: "왕복", scheduledDate: date(2026, 7, 20, 10, 0), rolloverCount: 2)
        store.addTask(task)

        rollover.moveToBacklog(task)
        #expect(task.rolloverCount == 0)
        // 백로그에서 일반 재배정(오늘로)은 카운트를 올리지 않는다(§13.3 — rolloverToToday만 증가).
        task.scheduledDate = boundary.scheduledToday()
        store.notifyChanged()
        #expect(task.rolloverCount == 0)
    }

    @Test("버리기는 삭제가 아니라 취소 보관")
    func cancelKeepsHistory() {
        let task = TodoTask(title: "버리기 대상", scheduledDate: date(2026, 7, 21, 10, 0))
        store.addTask(task)

        rollover.cancel(task)
        #expect(task.status == .cancelled)
        #expect(task.cancelledAt == date(2026, 7, 22, 10, 0))
        #expect(store.tasks.map(\.id) == [task.id])
        #expect(store.cancelledTasks().map(\.id) == [task.id])
        #expect(rollover.unfinishedTasksFromPreviousDays().isEmpty)
    }

    @Test("일괄 이월")
    func rolloverAll() {
        let a = TodoTask(title: "a", scheduledDate: date(2026, 7, 20, 10, 0), rolloverCount: 1)
        let b = TodoTask(title: "b", scheduledDate: date(2026, 7, 21, 10, 0))
        [a, b].forEach(store.addTask)

        rollover.rolloverAllToToday(rollover.unfinishedTasksFromPreviousDays())
        #expect(a.rolloverCount == 2)
        #expect(b.rolloverCount == 1)
        #expect(rollover.unfinishedTasksFromPreviousDays().isEmpty)
        #expect(store.todayTasks(boundary: boundary).count == 2)
    }
}
