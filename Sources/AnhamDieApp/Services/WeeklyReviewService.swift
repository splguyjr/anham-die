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
    // 파일 소유 경계를 지키기 위해 AppSettings 대신 전용 UserDefaults 키로 자립 저장한다
    // (BriefingController 위치 저장 선례). lastBriefingDate(하루 1회)와 정합하는 주 1회 노출 상태.
    private let defaults: UserDefaults
    private static let lastWeekReviewKey = "AnhamDie.lastWeekReviewKey"

    init(
        store: TaskStore,
        dayBoundary: DayBoundaryService,
        settings: AppSettings,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.dayBoundary = dayBoundary
        self.settings = settings
        self.defaults = defaults
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
        let regenerated = regenerateRoutineGoals(forWeek: currentWeek)
        // 커밋 순서 규약: 재생성 결과를 디스크에 동기 플러시한 '뒤'에만 처리 완료를 기록한다.
        // 역순이면 store.json 디바운스(0.5s) 창에서 강제 종료 시 lastProcessedWeekStart만 전진해
        // 이번 주 회차가 미기록으로 남고, 다음 주 전환의 '회차 부재 = 시리즈 삭제' 판정에 걸려
        // 루틴이 영구 종료된다. 반대 순서의 크래시는 재실행 시 멱등 재처리(hasCurrentWeek 가드)로 복구된다.
        if regenerated { store.saveNow() }
        settings.lastProcessedWeekStart = currentWeek
    }

    /// 루틴 목표 재생성 (§20.3): 계보(routineSeriesID ?? id)별 '살아있는 루틴'의 최신 회차가
    /// 이전 주 것이면 이번 주 0/n 회차를 만든다. 이전 주 기록은 그대로 보존된다.
    /// 이번 주 회차가 이미 있으면 건너뛴다 — 중복 호출·주 시작 요일 변경에도 안전.
    ///
    /// 계보는 isRoutine 필터 없이 전체 목표에서 모으고, 재생성 여부는 '최신 회차'만 보고 판정한다.
    /// isRoutine으로 계보를 거르면 해제/삭제한 회차가 계보에서 빠져 과거 루틴 회차가 latest로
    /// 뽑혀 부활하는 버그가 난다. '살아있는 루틴' 조건:
    /// - latest.isRoutine == false → 사용자가 최근 회차의 루틴을 껐다 → 재생성 중단.
    /// - latest.status == .dropped → 종료된 루틴 → 재생성 중단.
    /// - latest.weekKey < lastProcessedWeekStart → 마지막으로 처리한 주의 회차가 사라졌다(=삭제).
    ///   살아있었다면 그 주 재생성으로 회차가 남아 있어야 하므로 시리즈 종료로 간주 → 재생성 중단.
    ///   (과거 회차만 지운 경우엔 latest가 여전히 최신 주라 이 조건에 걸리지 않고 계속된다.)
    /// 반환값: 이번 호출로 실제 재생성(또는 계보 id 채움)이 일어났는가 — 호출부의 동기 플러시 판단용.
    @discardableResult
    func regenerateRoutineGoals(forWeek currentWeek: Date) -> Bool {
        var didRegenerate = false
        var lineages: [UUID: [WeeklyGoal]] = [:]
        for goal in store.weeklyGoals {
            lineages[goal.routineSeriesID ?? goal.id, default: []].append(goal)
        }
        let lastProcessed = settings.lastProcessedWeekStart
            .map { dayBoundary.logicalDay(ofStored: $0) }
        for (seriesID, goals) in lineages {
            let hasCurrentWeek = goals.contains {
                dayBoundary.logicalDay(ofStored: $0.weekKey) == currentWeek
            }
            guard !hasCurrentWeek else { continue }
            guard let latest = goals.max(by: {
                ($0.weekKey, $0.createdAt) < ($1.weekKey, $1.createdAt)
            }) else { continue }
            let latestWeek = dayBoundary.logicalDay(ofStored: latest.weekKey)
            guard latest.isRoutine, latest.status != .dropped, latestWeek < currentWeek
            else { continue }
            if let lastProcessed, latestWeek < lastProcessed { continue }
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
            didRegenerate = true
        }
        return didRegenerate
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
    /// 원본에 연결된 활성 task(예: [오늘 하기]로 만들어 이월된 task)는 새 목표로 재연결한다 —
    /// 이월 후 완료 확정 +1이 지난 주 기록(사후 미달→달성 뒤집힘)이 아니라 새 목표에 오르게 (§20.2).
    /// 완료·취소된 task는 그대로 둔다 — 이미 오른 +1의 되돌리기 -1이 같은(원본) 목표에 가야 한다.
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
        for task in store.tasks where task.isActive && task.weeklyGoalID == goal.id {
            task.weeklyGoalID = fresh.id
        }
        store.addWeeklyGoal(fresh) // notifyChanged 포함 — 원본 status·task 재연결도 함께 영속
        return fresh
    }

    /// 종료 (§20.3): 기록은 보존하되 이월 후보에서 제외. 루틴이었다면 재생성도 중단된다.
    func drop(_ goal: WeeklyGoal) {
        goal.status = .dropped
        store.notifyChanged()
    }

    // MARK: - '지난주 리뷰' 노출 상태 (§20.3·§20.4 — 주당 1회)

    /// '지난주 리뷰' 섹션을 마지막으로 노출한 논리적 주의 시작 키. nil = 아직 노출한 적 없음.
    private var lastWeekReviewKey: Date? {
        get { defaults.object(forKey: Self.lastWeekReviewKey) as? Date }
        set {
            if let d = newValue {
                defaults.set(d, forKey: Self.lastWeekReviewKey)
            } else {
                defaults.removeObject(forKey: Self.lastWeekReviewKey)
            }
        }
    }

    /// 이번 논리적 주에 '지난주 리뷰'를 아직 노출하지 않았는가 (주당 1회 판정, §20.4).
    /// 브리핑은 여기에 더해 리뷰할 내용(후보·지난주 목표) 유무를 함께 보고 활성화한다.
    func shouldPresentWeekReview() -> Bool {
        lastWeekReviewKey != dayBoundary.currentWeekStart()
    }

    /// 리뷰 노출을 이번 주로 기록한다 — 실제 노출을 확정한 브리핑이 1회 호출.
    /// 이후 같은 주의 브리핑에선 다시 뜨지 않고, 보류한 후보는 다음 주 리뷰에 재등장한다.
    func markWeekReviewed() {
        lastWeekReviewKey = dayBoundary.currentWeekStart()
    }
}
