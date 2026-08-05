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

    /// 보류: 날짜 없는 백로그로 이동.
    /// 백로그는 '미룬 날'이 없으므로 이월 이력을 초기화한다(§13.3) — 이후 오늘로 가져와도 ↺ 배지 없음.
    func moveToBacklog(_ task: TodoTask) {
        task.scheduledDate = nil
        task.rolloverCount = 0
        store.notifyChanged()
    }

    /// 버리기: 삭제가 아니라 취소 상태로 히스토리에 보관 (복구 가능).
    /// 반복 태스크는 버려도 다음 회차가 정상 생성된다 (PLAN §11.5).
    func cancel(_ task: TodoTask) {
        task.markCancelled(at: dayBoundary.now())
        store.notifyChanged()
        recurrence.scheduleNextOccurrence(after: task)
    }

    /// 경계 복귀 (PLAN §22.3): '언젠가'에서 꺼냈으나(somedayOrigin) 미완료로 과거 논리적 하루에
    /// 남은 task를 일반 이월/overdue가 아니라 '언젠가'로 되돌린다 — rolloverCount 불변.
    /// TriggerService의 기존 경계 처리 경로에 편승해 호출된다(새 타이머 없음). 멱등:
    /// 복귀 후 scheduledDate가 nil이 되어 재호출돼도 대상에서 빠진다. 완료 task는 그대로 히스토리.
    func returnOverdueSomedayTasks() {
        let today = dayBoundary.logicalToday()
        for task in store.tasks where task.somedayOrigin && task.isActive {
            guard let scheduled = task.scheduledDate else { continue }
            if dayBoundary.logicalDay(ofStored: scheduled) < today {
                store.returnToSomeday(task)
            }
        }
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
