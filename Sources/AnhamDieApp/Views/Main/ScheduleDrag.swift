import Foundation

// "해야할 일" 리스트의 날짜 간 이동 규칙 (PLAN §12.6):
// "같은 그룹 내 드래그 = 수동 정렬(reorder, §11.3) / 다른 날짜 그룹으로 드래그 = 날짜 변경(reschedule)".
// 판정은 순수 함수, 적용은 MainActor 헬퍼. 순서 변경 자체는 기존 TaskReorderDropDelegate가 담당하고,
// 여기 apply는 reschedule(= scheduledDate 변경)만 수행한다.

/// "해야할 일" 3섹션의 소속 그룹 (PLAN §12.4). upcoming의 연관 값은 논리적 날짜(자정 키).
enum ScheduleGroup: Equatable, Hashable {
    case past
    case today
    case upcoming(Date)
}

/// 날짜 간 드래그 판정 결과.
enum ScheduleDragAction: Equatable {
    /// 같은 그룹 — 수동 정렬 (위치 조정은 TaskReorderDropDelegate가 수행)
    case reorder
    /// 다른 날짜 그룹 — scheduledDate를 to로 변경
    case reschedule(to: Date)
}

enum ScheduleDrag {
    /// 그룹에 대응하는 scheduledDate 저장 값(자정 날짜 키 규약). past는 단일 날짜가 없어 nil.
    static func rescheduleDate(for group: ScheduleGroup, boundary: DayBoundaryService) -> Date? {
        switch group {
        case .past:
            return nil
        case .today:
            return boundary.scheduledToday()
        case .upcoming(let day):
            return boundary.scheduledDateValue(for: day)
        }
    }

    /// 순수 판정: 같은 그룹이면 reorder, 다른 날짜 그룹이면 reschedule.
    /// 재배정 대상 날짜가 없는 그룹(past)으로의 드롭은 reorder로 처리한다(과거로의 날짜 변경은 정의되지 않음).
    static func action(
        from source: ScheduleGroup,
        to target: ScheduleGroup,
        boundary: DayBoundaryService
    ) -> ScheduleDragAction {
        if source == target { return .reorder }
        if let date = rescheduleDate(for: target, boundary: boundary) {
            return .reschedule(to: date)
        }
        return .reorder
    }

    /// 적용: reschedule일 때만 scheduledDate를 바꾸고 저장한다. reorder는 호출부가 TaskReorderDropDelegate로 처리.
    /// 판정 결과를 반환하므로 호출부가 reorder 분기를 이어갈 수 있다.
    @MainActor
    @discardableResult
    static func apply(
        dragged: TodoTask,
        from source: ScheduleGroup,
        to target: ScheduleGroup,
        store: TaskStore,
        boundary: DayBoundaryService
    ) -> ScheduleDragAction {
        let result = action(from: source, to: target, boundary: boundary)
        if case .reschedule(let date) = result {
            dragged.scheduledDate = date
            store.notifyChanged()
        }
        return result
    }
}

extension TaskStore {
    /// 태스크가 현재 속한 "해야할 일" 그룹. 백로그·완료·취소 등 리스트 밖이면 nil.
    /// scheduleSections/todoSectionsV4 단일 소스로 판정해 UI 섹션 배치와 항상 일치한다
    /// (예: 어제 scheduled + 오늘 due는 .today).
    func scheduleGroup(of task: TodoTask, boundary: DayBoundaryService, tagFilter: Tag? = nil) -> ScheduleGroup? {
        let sections = todoSectionsV4(boundary: boundary, tagFilter: tagFilter)
        if sections.past.contains(where: { $0.id == task.id }) { return .past }
        if sections.today.contains(where: { $0.id == task.id }) { return .today }
        if let item = sections.upcoming.first(where: { $0.task.id == task.id }) {
            return .upcoming(item.day)
        }
        return nil
    }
}
