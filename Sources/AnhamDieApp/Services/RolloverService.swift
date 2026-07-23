import Foundation

/// 이전 논리적 하루의 미완료 태스크를 조회하고 이월/보류/취소 처리한다 (PLAN §2.3).
@MainActor
final class RolloverService {
    private let store: TaskStore
    private let dayBoundary: DayBoundaryService
    private let recurrence: RecurrenceService

    init(store: TaskStore, dayBoundary: DayBoundaryService) {
        self.store = store
        self.dayBoundary = dayBoundary
        self.recurrence = RecurrenceService(store: store, dayBoundary: dayBoundary)
    }

    /// 오늘 이전 논리적 하루에 예정되었으나 아직 미완료(active)인 태스크
    func unfinishedTasksFromPreviousDays() -> [TodoTask] {
        let today = dayBoundary.logicalToday()
        return store.tasks.filter { task in
            guard task.isActive, let scheduled = task.scheduledDate else { return false }
            return dayBoundary.logicalDay(ofStored: scheduled) < today
        }
        .sorted { ($0.scheduledDate ?? .distantPast, $0.sortOrder) < ($1.scheduledDate ?? .distantPast, $1.sortOrder) }
    }

    /// 오늘로 가져오기: scheduledDate = 오늘, rolloverCount += 1 (↺n 배지)
    func rolloverToToday(_ task: TodoTask) {
        task.scheduledDate = dayBoundary.scheduledToday()
        task.rolloverCount += 1
        store.notifyChanged()
    }

    /// 보류: 날짜 없는 백로그로 이동
    func moveToBacklog(_ task: TodoTask) {
        task.scheduledDate = nil
        store.notifyChanged()
    }

    /// 버리기: 삭제가 아니라 취소 상태로 히스토리에 보관 (복구 가능).
    /// 반복 태스크는 버려도 다음 회차가 정상 생성된다 (PLAN §11.5).
    func cancel(_ task: TodoTask) {
        task.markCancelled(at: dayBoundary.now())
        store.notifyChanged()
        recurrence.scheduleNextOccurrence(after: task)
    }

    func rolloverAllToToday(_ tasks: [TodoTask]) {
        tasks.forEach(rolloverToToday)
    }

    func moveAllToBacklog(_ tasks: [TodoTask]) {
        tasks.forEach(moveToBacklog)
    }

    func cancelAll(_ tasks: [TodoTask]) {
        tasks.forEach(cancel)
    }
}
