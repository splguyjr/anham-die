import Foundation

/// 주 전환 처리 (v11 §20.3). 새 타이머 없이 기존 하루 경계 경로에 편승한다 —
/// TriggerService.handle(모든 트리거)이 processWeekTransitionIfNeeded()를 호출하고,
/// settings.lastProcessedWeekStart로 멱등을 보장한다 (앱을 몇 주 껐다 켜도 1회 처리).
/// - 루틴 목표: 새 주 시작 시 0/n 재생성 (이전 주 기록 보존).
/// - 비루틴 미달 목표: carryOverCandidates()가 후보를 제공하고, 새 주 첫 브리핑의
///   '지난주 리뷰' 섹션(브리핑 모듈)이 [이월(잔여량만)/보류/종료] UI를 담당한다.
///   보류 = 아무 처리 안 함 — 목표는 지난 주에 active로 남아 다음 리뷰에 다시 후보가 된다.
@MainActor
final class WeeklyReviewService {
    private let store: TaskStore
    private let dayBoundary: DayBoundaryService
    private let settings: AppSettings

    init(store: TaskStore, dayBoundary: DayBoundaryService, settings: AppSettings) {
        self.store = store
        self.dayBoundary = dayBoundary
        self.settings = settings
    }

    /// 주 경계 통과 시 1회 처리(멱등). 경계 타이머·웨이크·앱 실행 트리거마다 불려도 안전하다.
    /// 주 시작 요일 설정 변경으로 현재 주 키가 바뀌면 새 주로 간주해 재처리한다(재생성 가드가 중복 방지).
    func processWeekTransitionIfNeeded() {
        let currentWeek = dayBoundary.currentWeekStart()
        guard let last = settings.lastProcessedWeekStart else {
            // 최초 실행(또는 v11 업데이트 직후): 전환할 이전 주가 없다 — 기준점만 기록.
            settings.lastProcessedWeekStart = currentWeek
            return
        }
        guard dayBoundary.logicalDay(ofStored: last) != currentWeek else { return }
        regenerateRoutineGoals(forWeek: currentWeek)
        settings.lastProcessedWeekStart = currentWeek
    }

    /// 루틴 목표 재생성 (§20.3): 계보(routineSeriesID ?? id)별 최신 회차가 이전 주 것이고
    /// dropped가 아니면 이번 주 0/n 회차를 만든다. 이전 주 기록은 그대로 보존된다.
    /// 이번 주 회차가 이미 있으면 건너뛴다 — 중복 호출·주 시작 요일 변경에도 안전.
    func regenerateRoutineGoals(forWeek currentWeek: Date) {
        var lineages: [UUID: [WeeklyGoal]] = [:]
        for goal in store.weeklyGoals where goal.isRoutine {
            lineages[goal.routineSeriesID ?? goal.id, default: []].append(goal)
        }
        for (seriesID, goals) in lineages {
            let hasCurrentWeek = goals.contains {
                dayBoundary.logicalDay(ofStored: $0.weekKey) == currentWeek
            }
            guard !hasCurrentWeek else { continue }
            guard let latest = goals.max(by: {
                ($0.weekKey, $0.createdAt) < ($1.weekKey, $1.createdAt)
            }) else { continue }
            guard dayBoundary.logicalDay(ofStored: latest.weekKey) < currentWeek,
                  latest.status != .dropped else { continue }
            if latest.routineSeriesID == nil {
                latest.routineSeriesID = seriesID
            }
            let fresh = WeeklyGoal(
                title: latest.title,
                targetCount: latest.targetCount,
                weekKey: dayBoundary.scheduledDateValue(for: currentWeek),
                isRoutine: true,
                createdAt: dayBoundary.now(),
                routineSeriesID: seriesID
            )
            store.addWeeklyGoal(fresh)
        }
    }

    /// '지난주 리뷰' 이월 후보 (§20.3): 이전 주(들)의 비루틴·active·미달 목표.
    /// weekKey 오름차순(오래된 주 먼저) → createdAt 순. 브리핑 모듈이 UI를 얹는다.
    func carryOverCandidates() -> [WeeklyGoal] {
        let currentWeek = dayBoundary.currentWeekStart()
        return store.weeklyGoals
            .filter { goal in
                !goal.isRoutine && goal.status == .active && !goal.isAchieved
                    && dayBoundary.logicalDay(ofStored: goal.weekKey) < currentWeek
            }
            .sorted { ($0.weekKey, $0.createdAt) < ($1.weekKey, $1.createdAt) }
    }

    /// 이번 주로 이월(잔여량만, §20.3): 새 목표 target = 원본 target - current (최소 1),
    /// 진행 0에서 재시작. 원본은 carriedOver로 표시돼 기록만 남는다 (달성률 히스토리 보존).
    @discardableResult
    func carryOver(_ goal: WeeklyGoal) -> WeeklyGoal {
        let fresh = WeeklyGoal(
            title: goal.title,
            targetCount: max(1, goal.remainingCount),
            weekKey: dayBoundary.scheduledDateValue(for: dayBoundary.currentWeekStart()),
            isRoutine: false,
            createdAt: dayBoundary.now()
        )
        goal.status = .carriedOver
        store.addWeeklyGoal(fresh) // notifyChanged 포함 — 원본 status 변경도 함께 영속
        return fresh
    }

    /// 종료 (§20.3): 기록은 보존하되 이월 후보에서 제외. 루틴이었다면 재생성도 중단된다.
    func drop(_ goal: WeeklyGoal) {
        goal.status = .dropped
        store.notifyChanged()
    }
}
