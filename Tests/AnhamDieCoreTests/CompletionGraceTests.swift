import Foundation
import Testing
@testable import AnhamDieApp

// PLAN §11.6 — 완료 유예: 체크 → 유예 → 확정, 유예 중 재클릭 취소.

@MainActor
@Suite("완료 유예 (CompletionGraceController)")
struct CompletionGraceTests {
    func makeEnv(grace: TimeInterval = 0.05)
        -> (JSONTaskStore, DayBoundaryService, CompletionGraceController)
    {
        let settings = makeTestSettings()
        let store = makeTempStore()
        let boundary = DayBoundaryService(settings: settings, now: { date(2026, 7, 23, 14) })
        let recurrence = RecurrenceService(store: store, dayBoundary: boundary)
        let controller = CompletionGraceController(
            store: store, dayBoundary: boundary, recurrence: recurrence, graceInterval: grace
        )
        return (store, boundary, controller)
    }

    @Test("체크 → 유예 중(active 유지·pending) → 유예 후 완료 확정")
    func graceThenConfirm() async throws {
        let (store, boundary, controller) = makeEnv()
        let task = TodoTask(title: "T", scheduledDate: boundary.scheduledToday())
        store.addTaskApplyingInitialOrder(task)

        controller.toggleCompletion(of: task)
        #expect(controller.isPending(task))
        #expect(task.isActive) // 확정 전에는 목록에서 사라지지 않는다

        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!controller.isPending(task))
        #expect(task.isCompleted)
        #expect(task.completedAt == date(2026, 7, 23, 14))
    }

    @Test("유예 중 재클릭 = 완료 취소 (active 유지)")
    func reclickCancels() async throws {
        let (store, boundary, controller) = makeEnv()
        let task = TodoTask(title: "T", scheduledDate: boundary.scheduledToday())
        store.addTaskApplyingInitialOrder(task)

        controller.toggleCompletion(of: task)
        controller.toggleCompletion(of: task)
        #expect(!controller.isPending(task))

        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(task.isActive)
        #expect(task.completedAt == nil)
    }

    @Test("완료된 task 재클릭 = 완료 해제")
    func toggleCompletedReactivates() {
        let (store, boundary, controller) = makeEnv()
        let task = TodoTask(title: "T", scheduledDate: boundary.scheduledToday())
        store.addTaskApplyingInitialOrder(task)
        task.markCompleted(at: boundary.now())

        controller.toggleCompletion(of: task)
        #expect(task.isActive)
        #expect(!controller.isPending(task))
    }

    @Test("flushAll: 유예 무시하고 즉시 확정 (앱 종료 경로)")
    func flushAllConfirmsImmediately() {
        let (store, boundary, controller) = makeEnv(grace: 60)
        let task = TodoTask(title: "T", scheduledDate: boundary.scheduledToday())
        store.addTaskApplyingInitialOrder(task)

        controller.toggleCompletion(of: task)
        controller.flushAll()
        #expect(task.isCompleted)
        #expect(!controller.isPending(task))
    }

    @Test("확정 시 반복 다음 발생이 생성된다 (§11.5 연동)")
    func confirmTriggersRecurrence() async throws {
        let (store, boundary, controller) = makeEnv()
        let task = TodoTask(
            title: "매일", scheduledDate: boundary.scheduledToday(), recurrence: .daily
        )
        store.addTaskApplyingInitialOrder(task)

        controller.toggleCompletion(of: task)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(task.isCompleted)
        let next = store.tasks.first { $0.id != task.id }
        #expect(next?.scheduledDate.map { boundary.logicalDay(ofStored: $0) } == midnight(2026, 7, 24))
    }
}
