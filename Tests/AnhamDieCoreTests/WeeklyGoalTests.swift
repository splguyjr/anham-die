import Foundation
import Testing
@testable import AnhamDieApp

// v11 주간 목표 (PLAN §20) — 논리적 주 계산·store v3 마이그레이션·카운트 증감/유예 연동·
// 루틴 재생성·잔여량 이월. 기준 시각은 사용자 규약대로 06:00을 주로 쓴다.
// 2026-08-03(월)·2026-07-27(월)이 기준 주다.

// MARK: - 논리적 주 계산 (§20.1)

@Suite("논리적 주 (DayBoundaryService)")
struct LogicalWeekTests {
    private func makeBoundary(
        hour: Int = 6, weekStartDay: Int = 2, now: Date
    ) -> DayBoundaryService {
        let settings = makeTestSettings(boundaryHour: hour)
        settings.weekStartDay = weekStartDay
        return DayBoundaryService(settings: settings, now: { now })
    }

    @Test("월요일 기준 시각 전은 이전 주")
    func mondayBeforeBoundaryIsPreviousWeek() {
        let boundary = makeBoundary(now: date(2026, 8, 3, 5, 59))
        #expect(boundary.currentWeekStart() == midnight(2026, 7, 27))
    }

    @Test("월요일 기준 시각 정각부터 새 주")
    func mondayAtBoundaryIsNewWeek() {
        let boundary = makeBoundary(now: date(2026, 8, 3, 6, 0))
        #expect(boundary.currentWeekStart() == midnight(2026, 8, 3))
    }

    @Test("월요일 새벽(자정~기준 시각)은 이전 주 — 하루 소속을 먼저 판정")
    func mondayEarlyMorningStillPreviousWeek() {
        let boundary = makeBoundary(now: date(2026, 8, 3, 2, 0))
        #expect(boundary.logicalWeekStart(of: date(2026, 8, 3, 2, 0)) == midnight(2026, 7, 27))
    }

    @Test("주중·일요일 밤 모두 그 주 월요일 키")
    func midWeekAndSundayNightSameWeek() {
        let boundary = makeBoundary(now: date(2026, 7, 30, 12, 0))
        #expect(boundary.currentWeekStart() == midnight(2026, 7, 27))
        #expect(boundary.logicalWeekStart(of: date(2026, 8, 2, 23, 0)) == midnight(2026, 7, 27))
        #expect(boundary.isSameLogicalWeek(date(2026, 7, 27, 8, 0), date(2026, 8, 3, 2, 0)))
        #expect(!boundary.isSameLogicalWeek(date(2026, 7, 27, 8, 0), date(2026, 8, 3, 7, 0)))
    }

    @Test("weekStart(ofDay:)는 자정 날짜 키 규약 — 경계 오프셋 무관")
    func weekStartOfDayIsBoundaryIndependent() {
        let at6 = makeBoundary(hour: 6, now: date(2026, 7, 30, 12, 0))
        let at9 = makeBoundary(hour: 9, now: date(2026, 7, 30, 12, 0))
        for day in [midnight(2026, 8, 3), midnight(2026, 8, 5), midnight(2026, 8, 9)] {
            #expect(at6.weekStart(ofDay: day) == midnight(2026, 8, 3))
            #expect(at9.weekStart(ofDay: day) == midnight(2026, 8, 3))
        }
    }

    @Test("주 시작 요일 설정 반영 — 일요일 시작")
    func customWeekStartDaySunday() {
        let boundary = makeBoundary(weekStartDay: 1, now: date(2026, 8, 2, 12, 0))
        #expect(boundary.currentWeekStart() == midnight(2026, 8, 2))
        #expect(boundary.weekStart(ofDay: midnight(2026, 8, 8)) == midnight(2026, 8, 2))
        #expect(boundary.weekStart(ofDay: midnight(2026, 8, 9)) == midnight(2026, 8, 9))
    }

    @Test("이전/다음 주 계산")
    func previousAndNextWeek() {
        let boundary = makeBoundary(now: date(2026, 8, 4, 12, 0))
        let week = boundary.currentWeekStart()
        #expect(week == midnight(2026, 8, 3))
        #expect(boundary.previousWeekStart(before: week) == midnight(2026, 7, 27))
        #expect(boundary.nextWeekStart(after: week) == midnight(2026, 8, 10))
    }

    @Test("weekStartDay 설정은 1~7로 클램프된다")
    func weekStartDayClamped() {
        let settings = makeTestSettings()
        settings.weekStartDay = 0
        #expect(settings.weekStartDay == 1)
        settings.weekStartDay = 8
        #expect(settings.weekStartDay == 7)
    }
}

// MARK: - 모델·카운트 API (§20.1·§20.2)

@MainActor
@Suite("주간 목표 모델·카운트")
struct WeeklyGoalCountTests {
    private let store: JSONTaskStore
    private let boundary: DayBoundaryService

    init() {
        store = makeTempStore()
        boundary = DayBoundaryService(
            settings: makeTestSettings(boundaryHour: 6), now: { date(2026, 8, 4, 12, 0) })
    }

    private func addGoal(target: Int = 3, isRoutine: Bool = false) -> WeeklyGoal {
        let goal = WeeklyGoal(
            title: "헬스", targetCount: target,
            weekKey: boundary.scheduledDateValue(for: boundary.currentWeekStart()),
            isRoutine: isRoutine, createdAt: boundary.now()
        )
        store.addWeeklyGoal(goal)
        return goal
    }

    @Test("targetCount는 최소 1로 클램프")
    func targetCountClamped() {
        let goal = WeeklyGoal(title: "G", targetCount: 0, weekKey: midnight(2026, 8, 3))
        #expect(goal.targetCount == 1)
    }

    @Test("완주 판정·잔여량 — 초과 달성 포함")
    func achievementAndRemaining() {
        let goal = addGoal(target: 3)
        #expect(!goal.isAchieved)
        #expect(goal.remainingCount == 3)
        goal.currentCount = 3
        #expect(goal.isAchieved)
        goal.currentCount = 5 // 초과 달성도 완주, 잔여 0
        #expect(goal.isAchieved)
        #expect(goal.remainingCount == 0)
    }

    @Test("increment는 target 초과를 허용, decrement는 0 미만 방지")
    func incrementDecrementBounds() {
        let goal = addGoal(target: 2)
        for _ in 0..<3 { store.incrementGoalCount(id: goal.id) }
        #expect(goal.currentCount == 3) // 초과 달성 허용 (클램프 아님)
        for _ in 0..<5 { store.decrementGoalCount(id: goal.id) }
        #expect(goal.currentCount == 0) // 음수 방지
    }

    @Test("주별 조회는 해당 주 목표만 createdAt 순으로")
    func goalsForWeekFiltersAndSorts() {
        let thisWeek = addGoal()
        let lastWeekGoal = WeeklyGoal(
            title: "지난주", weekKey: midnight(2026, 7, 27), createdAt: date(2026, 7, 27, 7)
        )
        store.addWeeklyGoal(lastWeekGoal)
        let current = store.weeklyGoals(forWeek: midnight(2026, 8, 3), boundary: boundary)
        #expect(current.map(\.id) == [thisWeek.id])
        let grouped = store.weeklyGoalsGroupedByWeek(boundary: boundary)
        #expect(grouped.map(\.week) == [midnight(2026, 8, 3), midnight(2026, 7, 27)])
    }

    @Test("[오늘 하기] — 오늘 task 생성·연결, 재호출은 중복 생성 없이 기존 반환")
    func createLinkedTaskIdempotent() {
        let goal = addGoal()
        let task = store.createLinkedTask(goal: goal, boundary: boundary)
        #expect(task.weeklyGoalID == goal.id)
        #expect(task.scheduledDate.map { boundary.logicalDay(ofStored: $0) } == boundary.logicalToday())
        #expect(task.title == goal.title)

        let again = store.createLinkedTask(goal: goal, boundary: boundary)
        #expect(again.id == task.id)
        #expect(store.tasks.count == 1)

        // 오늘 연결 task가 완료되면 새로 만들 수 있다 (횟수형 — 하루 1회 이상도 가능)
        task.markCompleted(at: boundary.now())
        let third = store.createLinkedTask(goal: goal, boundary: boundary)
        #expect(third.id != task.id)
    }

    @Test("목표 삭제 시 연결 task의 참조가 끊긴다")
    func removeGoalDetachesTasks() {
        let goal = addGoal()
        let task = store.createLinkedTask(goal: goal, boundary: boundary)
        store.removeWeeklyGoal(goal)
        #expect(store.weeklyGoal(withID: goal.id) == nil)
        #expect(task.weeklyGoalID == nil)
    }
}

// MARK: - 완료 유예 연동 (§20.2)

@MainActor
@Suite("주간 목표 × 완료 유예")
struct WeeklyGoalGraceTests {
    private func makeEnv(grace: TimeInterval = 0.05)
        -> (JSONTaskStore, DayBoundaryService, CompletionGraceController, WeeklyGoal)
    {
        let store = makeTempStore()
        let boundary = DayBoundaryService(
            settings: makeTestSettings(boundaryHour: 6), now: { date(2026, 8, 4, 12, 0) })
        let recurrence = RecurrenceService(store: store, dayBoundary: boundary)
        let controller = CompletionGraceController(
            store: store, dayBoundary: boundary, recurrence: recurrence, graceInterval: grace
        )
        let goal = WeeklyGoal(
            title: "코테 3문제", targetCount: 3,
            weekKey: boundary.scheduledDateValue(for: boundary.currentWeekStart())
        )
        store.addWeeklyGoal(goal)
        return (store, boundary, controller, goal)
    }

    @Test("연결 task 완료 '확정' 시 +1")
    func confirmIncrementsGoal() async throws {
        let (store, boundary, controller, goal) = makeEnv()
        let task = store.createLinkedTask(goal: goal, boundary: boundary)
        controller.toggleCompletion(of: task)
        #expect(goal.currentCount == 0) // 유예 중에는 아직 오르지 않는다
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(task.isCompleted)
        #expect(goal.currentCount == 1)
    }

    @Test("유예 중 재클릭(완료 취소)은 카운트 무변")
    func graceCancelKeepsCount() async throws {
        let (store, boundary, controller, goal) = makeEnv()
        let task = store.createLinkedTask(goal: goal, boundary: boundary)
        controller.toggleCompletion(of: task)
        controller.toggleCompletion(of: task)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(task.isActive)
        #expect(goal.currentCount == 0)
    }

    @Test("완료 해제(reactivate) 시 -1")
    func reactivateDecrementsGoal() async throws {
        let (store, boundary, controller, goal) = makeEnv()
        let task = store.createLinkedTask(goal: goal, boundary: boundary)
        controller.toggleCompletion(of: task)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(goal.currentCount == 1)
        controller.toggleCompletion(of: task) // completed → reactivate
        #expect(task.isActive)
        #expect(goal.currentCount == 0)
    }

    @Test("flushAll(즉시 확정)도 +1")
    func flushAllIncrements() {
        let (store, boundary, controller, goal) = makeEnv(grace: 60)
        let task = store.createLinkedTask(goal: goal, boundary: boundary)
        controller.toggleCompletion(of: task)
        controller.flushAll()
        #expect(task.isCompleted)
        #expect(goal.currentCount == 1)
    }

    @Test("연결 task 삭제 후에도 이미 오른 카운트는 유지")
    func deletingTaskKeepsCount() async throws {
        let (store, boundary, controller, goal) = makeEnv()
        let task = store.createLinkedTask(goal: goal, boundary: boundary)
        controller.toggleCompletion(of: task)
        try await Task.sleep(nanoseconds: 300_000_000)
        store.removeTask(task)
        #expect(goal.currentCount == 1)
    }
}

// MARK: - store.json v3 마이그레이션 (§20.5)

@MainActor
@Suite("store.json v3 마이그레이션")
struct WeeklyGoalMigrationTests {
    @Test("v2 문서 로드 — 데이터 보존 + version 3 확정 + goals 빈 목록")
    func migratesV2Document() throws {
        let dir = makeTempStoreDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("store.json")
        let v2Content = """
        {
          "version" : 2,
          "tags" : [
            { "colorHex" : "#FF3B30", "id" : "AAAAAAAA-0000-0000-0000-000000000001", "name" : "업무" }
          ],
          "tasks" : [
            {
              "createdAt" : "2026-08-01T01:00:00Z",
              "id" : "BBBBBBBB-0000-0000-0000-000000000001",
              "note" : "",
              "priority" : 1,
              "recurrence" : { "kind" : "none" },
              "rolloverCount" : 0,
              "scheduledDate" : "2026-08-03T00:00:00Z",
              "sortOrder" : 0,
              "status" : "active",
              "subtasks" : [],
              "tagIDs" : [],
              "title" : "기존 태스크"
            }
          ]
        }
        """
        try v2Content.write(to: file, atomically: true, encoding: .utf8)

        let store = JSONTaskStore(directory: dir)
        #expect(!store.saveBlocked)
        #expect(store.tasks.count == 1)
        #expect(store.tags.count == 1)
        #expect(store.weeklyGoals.isEmpty)
        // v2 문서에 없던 weeklyGoalID는 nil로 흡수된다
        #expect(store.tasks[0].weeklyGoalID == nil)
        // sortOrder 등 기존 데이터는 그대로 (v2 마이그레이션 재실행 없음)
        #expect(store.tasks[0].title == "기존 태스크")

        // 디스크가 v3로 확정돼 구버전(≤1.3.0) 실행의 덮어쓰기(goals 유실)가 잠긴다
        let rewritten = try String(contentsOf: file, encoding: .utf8)
        #expect(rewritten.contains("\"version\" : 3"))
    }

    @Test("목표·연결 task 저장/재로드 왕복")
    func goalRoundTrip() throws {
        let dir = makeTempStoreDirectory()
        let store = JSONTaskStore(directory: dir)
        let goal = WeeklyGoal(
            title: "헬스 3회", targetCount: 3, currentCount: 2,
            weekKey: midnight(2026, 8, 3), isRoutine: true, status: .active,
            routineSeriesID: nil
        )
        store.addWeeklyGoal(goal)
        store.addTask(TodoTask(title: "헬스", weeklyGoalID: goal.id))
        store.saveNow()

        let reloaded = JSONTaskStore(directory: dir)
        #expect(reloaded.weeklyGoals.count == 1)
        let loaded = try #require(reloaded.weeklyGoal(withID: goal.id))
        #expect(loaded.title == "헬스 3회")
        #expect(loaded.targetCount == 3)
        #expect(loaded.currentCount == 2)
        #expect(loaded.isRoutine)
        #expect(loaded.status == .active)
        #expect(loaded.weekKey == midnight(2026, 8, 3))
        #expect(reloaded.tasks[0].weeklyGoalID == goal.id)
    }

    @Test("v1 문서도 v3까지 한 번에 — 기존 v1→v2 재부여 규칙 유지")
    func migratesV1DocumentToV3() throws {
        let dir = makeTempStoreDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("store.json")
        let v1Content = """
        {
          "version" : 1,
          "tags" : [],
          "tasks" : [
            {
              "createdAt" : "2026-07-20T01:00:00Z",
              "id" : "BBBBBBBB-0000-0000-0000-000000000009",
              "note" : "",
              "priority" : 2,
              "rolloverCount" : 0,
              "sortOrder" : 7,
              "status" : "active",
              "subtasks" : [],
              "tagIDs" : [],
              "title" : "v1 태스크"
            }
          ]
        }
        """
        try v1Content.write(to: file, atomically: true, encoding: .utf8)

        let store = JSONTaskStore(directory: dir)
        #expect(store.tasks.count == 1)
        #expect(store.tasks[0].sortOrder == 0) // v1→v2 초기 배치 재부여
        let rewritten = try String(contentsOf: file, encoding: .utf8)
        #expect(rewritten.contains("\"version\" : 3"))
    }
}

// MARK: - 주 전환: 루틴 재생성·잔여량 이월 (§20.3)

@MainActor
@Suite("주 전환 (WeeklyReviewService)")
struct WeeklyReviewServiceTests {
    private func makeEnv(now: Date = date(2026, 8, 4, 12, 0))
        -> (JSONTaskStore, DayBoundaryService, AppSettings, WeeklyReviewService, ClockBox)
    {
        let settings = makeTestSettings(boundaryHour: 6)
        let clock = ClockBox(now: now)
        let store = makeTempStore()
        let boundary = DayBoundaryService(settings: settings, now: { clock.now })
        let review = WeeklyReviewService(store: store, dayBoundary: boundary, settings: settings)
        return (store, boundary, settings, review, clock)
    }

    final class ClockBox {
        var now: Date
        init(now: Date) { self.now = now }
    }

    @Test("최초 실행은 기준점만 기록하고 재생성하지 않는다")
    func firstRunOnlyRecordsBaseline() {
        let (store, _, settings, review, _) = makeEnv()
        let routine = WeeklyGoal(
            title: "헬스 3회", targetCount: 3, weekKey: midnight(2026, 7, 27), isRoutine: true
        )
        store.addWeeklyGoal(routine)
        review.processWeekTransitionIfNeeded()
        #expect(settings.lastProcessedWeekStart == midnight(2026, 8, 3))
        #expect(store.weeklyGoals.count == 1)
    }

    @Test("새 주 진입 시 루틴 목표 0/n 재생성 — 이전 주 기록 보존·멱등")
    func routineRegeneration() throws {
        let (store, _, settings, review, _) = makeEnv()
        settings.lastProcessedWeekStart = midnight(2026, 7, 27)
        let routine = WeeklyGoal(
            title: "헬스 3회", targetCount: 3, currentCount: 2,
            weekKey: midnight(2026, 7, 27), isRoutine: true
        )
        store.addWeeklyGoal(routine)

        review.processWeekTransitionIfNeeded()

        #expect(settings.lastProcessedWeekStart == midnight(2026, 8, 3))
        #expect(store.weeklyGoals.count == 2)
        let fresh = try #require(store.weeklyGoals.first { $0.id != routine.id })
        #expect(fresh.weekKey == midnight(2026, 8, 3))
        #expect(fresh.currentCount == 0)
        #expect(fresh.targetCount == 3)
        #expect(fresh.isRoutine)
        #expect(fresh.routineSeriesID == routine.id) // 계보 승계
        #expect(routine.routineSeriesID == routine.id)
        // 이전 주 기록은 그대로
        #expect(routine.currentCount == 2)
        #expect(routine.weekKey == midnight(2026, 7, 27))

        // 멱등: 같은 주에 다시 불려도 중복 생성 없음
        review.processWeekTransitionIfNeeded()
        review.regenerateRoutineGoals(forWeek: midnight(2026, 8, 3))
        #expect(store.weeklyGoals.count == 2)
    }

    @Test("몇 주를 건너뛰어도 현재 주 1회차만 재생성 — dropped 루틴은 제외")
    func regenerationAfterGapAndDropExcluded() {
        let (store, _, settings, review, _) = makeEnv()
        settings.lastProcessedWeekStart = midnight(2026, 7, 20)
        let routine = WeeklyGoal(
            title: "헬스 3회", targetCount: 3, weekKey: midnight(2026, 7, 20), isRoutine: true
        )
        let ended = WeeklyGoal(
            title: "끝낸 루틴", targetCount: 2, weekKey: midnight(2026, 7, 20),
            isRoutine: true, status: .dropped
        )
        store.addWeeklyGoal(routine)
        store.addWeeklyGoal(ended)

        review.processWeekTransitionIfNeeded()

        let freshWeeks = store.weeklyGoals
            .filter { $0.routineSeriesID == routine.id && $0.id != routine.id }
            .map(\.weekKey)
        #expect(freshWeeks == [midnight(2026, 8, 3)]) // 중간 주(7/27)는 만들지 않는다
        #expect(store.weeklyGoals.filter { $0.title == "끝낸 루틴" }.count == 1)
    }

    @Test("이월 후보 — 비루틴·active·미달만, 이전 주 것만")
    func carryOverCandidates() {
        let (store, _, _, review, _) = makeEnv()
        let underachieved = WeeklyGoal(
            title: "책 1챕터", targetCount: 1, currentCount: 0, weekKey: midnight(2026, 7, 27)
        )
        let achieved = WeeklyGoal(
            title: "달성함", targetCount: 2, currentCount: 2, weekKey: midnight(2026, 7, 27)
        )
        let routine = WeeklyGoal(
            title: "루틴", targetCount: 3, weekKey: midnight(2026, 7, 27), isRoutine: true
        )
        let dropped = WeeklyGoal(
            title: "종료함", targetCount: 2, weekKey: midnight(2026, 7, 27), status: .dropped
        )
        let currentWeek = WeeklyGoal(
            title: "이번 주", targetCount: 2, weekKey: midnight(2026, 8, 3)
        )
        for goal in [underachieved, achieved, routine, dropped, currentWeek] {
            store.addWeeklyGoal(goal)
        }
        #expect(review.carryOverCandidates().map(\.id) == [underachieved.id])
    }

    @Test("이월은 잔여량만 — 원본은 carriedOver로 기록 보존")
    func carryOverKeepsOnlyRemaining() {
        let (store, _, _, review, _) = makeEnv()
        let goal = WeeklyGoal(
            title: "코테 5문제", targetCount: 5, currentCount: 3, weekKey: midnight(2026, 7, 27)
        )
        store.addWeeklyGoal(goal)

        let fresh = review.carryOver(goal)

        #expect(fresh.targetCount == 2) // target - current 만 남긴다
        #expect(fresh.currentCount == 0)
        #expect(fresh.weekKey == midnight(2026, 8, 3))
        #expect(!fresh.isRoutine)
        #expect(goal.status == .carriedOver)
        #expect(goal.currentCount == 3) // 지난 주 달성률 히스토리 보존
        // 이월된 원본은 더 이상 후보가 아니다
        #expect(review.carryOverCandidates().isEmpty)
    }

    @Test("종료(drop)는 후보에서 빠지고 기록은 남는다")
    func dropRemovesFromCandidates() {
        let (store, _, _, review, _) = makeEnv()
        let goal = WeeklyGoal(title: "책 1챕터", weekKey: midnight(2026, 7, 27))
        store.addWeeklyGoal(goal)
        #expect(review.carryOverCandidates().count == 1)
        review.drop(goal)
        #expect(review.carryOverCandidates().isEmpty)
        #expect(store.weeklyGoal(withID: goal.id) != nil)
    }

    @Test("주 경계 통과 시뮬레이션 — 경계 전 no-op, 경계 후 1회 처리")
    func boundaryCrossingViaClock() {
        let (store, _, settings, review, clock) = makeEnv(now: date(2026, 8, 3, 5, 0))
        settings.lastProcessedWeekStart = midnight(2026, 7, 27)
        store.addWeeklyGoal(WeeklyGoal(
            title: "헬스 3회", targetCount: 3, weekKey: midnight(2026, 7, 27), isRoutine: true
        ))

        review.processWeekTransitionIfNeeded() // 월 05:00 — 아직 이전 주
        #expect(store.weeklyGoals.count == 1)
        #expect(settings.lastProcessedWeekStart == midnight(2026, 7, 27))

        clock.now = date(2026, 8, 3, 6, 0) // 월 06:00 — 새 주
        review.processWeekTransitionIfNeeded()
        #expect(store.weeklyGoals.count == 2)
        #expect(settings.lastProcessedWeekStart == midnight(2026, 8, 3))
    }
}
