import Foundation
import Observation

/// 완료 유예 (PLAN §11.6) — 오버레이·메인 리스트 공용의 체크 토글 단일 경로.
/// 체크 → pendingTaskIDs에 올라가고 1.5초 뒤 완료 확정. 유예 중 재클릭 = 완료 취소.
/// 확정 전까지 task.status는 active 그대로라 목록에서 즉시 사라지지 않는다 —
/// 뷰는 isPending(_:)을 읽어 체크 표시·취소선·애니메이션을 그린다 (@Observable 관찰).
/// 확정 시 반복 규칙이 있으면 다음 발생을 생성하고 (§11.5),
/// weeklyGoalID가 있으면 목표 진행 +1 / 완료 취소(reactivate) 시 -1 한다 (§20.2).
@MainActor
@Observable
final class CompletionGraceController {
    static let shared = CompletionGraceController(
        store: AppContext.shared.store,
        dayBoundary: AppContext.shared.dayBoundary,
        recurrence: AppContext.shared.recurrence
    )

    /// 유예 중(체크됐지만 미확정)인 태스크 ID — 뷰 관찰 지점
    private(set) var pendingTaskIDs: Set<UUID> = []

    @ObservationIgnored private let store: TaskStore
    @ObservationIgnored private let dayBoundary: DayBoundaryService
    @ObservationIgnored private let recurrence: RecurrenceService
    @ObservationIgnored private let graceInterval: TimeInterval
    @ObservationIgnored private var pendingTimers: [UUID: Task<Void, Never>] = [:]

    init(
        store: TaskStore,
        dayBoundary: DayBoundaryService,
        recurrence: RecurrenceService,
        graceInterval: TimeInterval = 1.5
    ) {
        self.store = store
        self.dayBoundary = dayBoundary
        self.recurrence = recurrence
        self.graceInterval = graceInterval
    }

    func isPending(_ task: TodoTask) -> Bool {
        pendingTaskIDs.contains(task.id)
    }

    /// 체크 토글 단일 진입점:
    /// active → 유예 시작 · 유예 중 → 취소(active 유지) · completed → 완료 해제(reactivate)
    func toggleCompletion(of task: TodoTask) {
        if pendingTaskIDs.contains(task.id) {
            cancelPending(for: task.id)
        } else if task.isCompleted {
            task.reactivate()
            store.notifyChanged()
            // 완료 취소 시 연결 주간 목표 -1 (§20.2, 0 미만 방지는 store가 담당)
            if let goalID = task.weeklyGoalID {
                store.decrementGoalCount(id: goalID)
            }
        } else if task.isActive {
            beginGrace(for: task)
        }
    }

    /// 유예 취소 — 태스크는 active 그대로 남는다
    func cancelPending(for taskID: UUID) {
        pendingTimers.removeValue(forKey: taskID)?.cancel()
        pendingTaskIDs.remove(taskID)
    }

    /// 유예 중인 완료 전부 즉시 확정 (앱 종료·논리적 하루 경계 등)
    func flushAll() {
        for taskID in Array(pendingTaskIDs) {
            pendingTimers.removeValue(forKey: taskID)?.cancel()
            confirm(taskID: taskID)
        }
    }

    private func beginGrace(for task: TodoTask) {
        let taskID = task.id
        pendingTaskIDs.insert(taskID)
        let nanos = UInt64(graceInterval * 1_000_000_000)
        pendingTimers[taskID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            self?.pendingTimers[taskID] = nil
            self?.confirm(taskID: taskID)
        }
    }

    private func confirm(taskID: UUID) {
        guard pendingTaskIDs.remove(taskID) != nil else { return }
        guard let task = store.task(withID: taskID), task.isActive else { return }
        task.markCompleted(at: dayBoundary.now())
        store.notifyChanged()
        recurrence.scheduleNextOccurrence(after: task)
        // 완료 '확정'(유예 통과) 시에만 연결 주간 목표 +1 (§20.2) — 유예 중 취소는 카운트 무변.
        // 이월된 task는 같은 계보의 이번 주 회차로 재연결 후 +1 (§20.3과의 정합).
        if let goalID = store.goalIDForCompletionCount(of: task, boundary: dayBoundary) {
            store.incrementGoalCount(id: goalID)
        }
    }
}

// MARK: - 완료 +1 목표 해석 (§20.2 × §20.3)

extension TaskStore {
    /// 완료 확정 +1을 적용할 목표 id를 해석한다. 연결 목표의 주가 이미 지났고 같은 계보
    /// (routineSeriesID, 루틴 재생성 승계)의 이번 주 회차가 있으면 task.weeklyGoalID를 그 회차로
    /// 재연결하고 그 id를 돌려준다 — 이월된 연결 task의 완료가 '지난 주' 기록에 +1되어 이번 주
    /// 회차(0/n)는 그대로인 채 지난 기록만 오르는 것을 막는다. 비루틴 이월 후속 목표는
    /// WeeklyReviewService.carryOver가 이월 시점에 재연결하므로 여기 계보 탐색엔 안 걸린다.
    /// 이번 주 회차가 없으면(비루틴·종료·회차 삭제) 원래 목표 id 그대로 — 지난 주 기록의
    /// 사후 +1로 남는다(§20.2 '삭제해도 카운트 유지'와 같은 보존 방향).
    /// 재연결된 id는 이후 되돌리기 -1 경로(task.weeklyGoalID)와도 일치한다.
    func goalIDForCompletionCount(of task: TodoTask, boundary: DayBoundaryService) -> UUID? {
        guard let goalID = task.weeklyGoalID else { return nil }
        guard let goal = weeklyGoal(withID: goalID) else { return goalID }
        let currentWeek = boundary.currentWeekStart()
        guard boundary.logicalDay(ofStored: goal.weekKey) < currentWeek else { return goalID }
        let seriesID = goal.routineSeriesID ?? goal.id
        guard let currentGoal = weeklyGoals.first(where: {
            $0.id != goal.id
                && ($0.routineSeriesID ?? $0.id) == seriesID
                && boundary.logicalDay(ofStored: $0.weekKey) == currentWeek
        }) else { return goalID }
        task.weeklyGoalID = currentGoal.id // 영속은 호출부의 increment(notifyChanged)에 편승
        return currentGoal.id
    }
}
