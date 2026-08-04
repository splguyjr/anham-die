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
        if let goalID = task.weeklyGoalID {
            store.incrementGoalCount(id: goalID)
        }
    }
}
