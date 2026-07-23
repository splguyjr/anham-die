import Foundation

/// 반복 작업의 다음 발생 생성 (PLAN §11.5).
/// 완료·취소가 '확정'되는 지점(CompletionGraceController 확정, RolloverService.cancel,
/// 상세/컨텍스트 메뉴의 직접 완료·취소)에서 scheduleNextOccurrence(after:)를 호출한다.
@MainActor
final class RecurrenceService {
    private let store: TaskStore
    private let dayBoundary: DayBoundaryService

    init(store: TaskStore, dayBoundary: DayBoundaryService) {
        self.store = store
        self.dayBoundary = dayBoundary
    }

    /// 완료·취소된 task의 다음 발생 task를 생성해 반환한다.
    /// - 승계: 제목·메모·태그·우선순위·반복 규칙·시리즈ID. 서브태스크는 미완료 상태로 복제(새 ID).
    /// - 초기화: rolloverCount 0, dueDate 없음, scheduledDate = 다음 발생 논리적 날짜.
    /// - 다음 발생 날짜 기준: max(원본 scheduledDate의 논리적 날짜, 논리적 오늘) 이후 —
    ///   과거 회차를 늦게 정리해도 이미 지난 날짜로 생성되지 않는다.
    /// - 중복 방지 키 = (시리즈ID, 발생 논리적 날짜): 같은 키의 태스크가 이미 있으면 nil.
    @discardableResult
    func scheduleNextOccurrence(after task: TodoTask) -> TodoTask? {
        guard task.recurrence != .none else { return nil }

        let seriesID = task.recurrenceSeriesID ?? task.id
        if task.recurrenceSeriesID == nil {
            task.recurrenceSeriesID = seriesID
        }

        let today = dayBoundary.logicalToday()
        let base: Date
        if let scheduled = task.scheduledDate {
            base = max(dayBoundary.logicalDay(ofStored: scheduled), today)
        } else {
            base = today
        }
        guard let nextDay = task.recurrence.nextOccurrence(after: base, calendar: dayBoundary.calendar)
        else { return nil }

        let duplicateExists = store.tasks.contains { other in
            other.id != task.id
                && other.recurrenceSeriesID == seriesID
                && other.scheduledDate.map { dayBoundary.logicalDay(ofStored: $0) } == nextDay
        }
        guard !duplicateExists else {
            store.notifyChanged() // 시리즈ID 최초 부여분 영속화
            return nil
        }

        let next = TodoTask(
            title: task.title,
            note: task.note,
            createdAt: dayBoundary.now(),
            scheduledDate: dayBoundary.scheduledDateValue(for: nextDay),
            priority: task.priority,
            tagIDs: task.tagIDs,
            subtasks: task.subtasks.map {
                Subtask(title: $0.title, isDone: false, sortOrder: $0.sortOrder)
            },
            recurrence: task.recurrence,
            recurrenceSeriesID: seriesID
        )
        store.addTaskApplyingInitialOrder(next)
        return next
    }
}
