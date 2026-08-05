import Foundation
import Testing
@testable import AnhamDieApp

// §13.3 회귀 잠금 — UI 행 액션 헬퍼(RowAction) 경로:
// 우클릭 '백로그로'(RowAction.moveToBacklog)가 RolloverService.moveToBacklog와 동일하게
// rolloverCount를 0으로 리셋해 백로그 불변식(백로그 항목엔 ↺ 배지 없음)을 지키는지 검증한다.
// 브리핑 경로(RolloverServiceTests)와 별개로 UI 경로에서 이월 이력이 새어나가던 회귀를 막는다.
// 백로그 이동 4개 쓰기 지점(RolloverService·우클릭 RowAction·상세 뷰 액션바·날짜 팝오버 '지우기')이
// 모두 이 헬퍼로 수렴함을 잠근다 — 어느 경로든 인라인 scheduledDate=nil로 되돌아가면 불변식이 다시 샌다.

@MainActor
@Suite("행 액션 헬퍼 — 백로그 이월 리셋")
struct RowActionsTests {
    private let store: JSONTaskStore
    private let boundary: DayBoundaryService

    init() {
        store = makeTempStore()
        boundary = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
    }

    @Test("우클릭 '백로그로'는 scheduledDate와 rolloverCount를 함께 리셋한다 (§13.3)")
    func moveToBacklogResetsRolloverCount() {
        let task = TodoTask(title: "이월 이력 있음", scheduledDate: boundary.scheduledToday(), rolloverCount: 3)
        store.addTask(task)

        RowAction.moveToBacklog(task, store: store)

        #expect(task.scheduledDate == nil)
        #expect(task.rolloverCount == 0)
        #expect(task.isActive)
        #expect(store.backlogTasks().map(\.id) == [task.id])
    }

    // 브리핑에서 이월(count=1) → UI '백로그로' → UI '오늘로'가 재현하던 정확한 경로.
    // 수정 전엔 '백로그로'가 count를 유지해 오늘 리스트에 ↺1이 다시 떴다.
    @Test("이월된 태스크의 UI 백로그 왕복 후 '오늘로'는 ↺ 배지가 없다 (§13.3)")
    func backlogRoundTripViaRowActionHasNoRolloverBadge() {
        let task = TodoTask(title: "왕복", scheduledDate: boundary.scheduledToday(), rolloverCount: 1)
        store.addTask(task)

        RowAction.moveToBacklog(task, store: store)
        #expect(task.rolloverCount == 0)

        RowAction.moveToToday(task, store: store, boundary: boundary)
        #expect(task.rolloverCount == 0)  // 일반 재배정은 카운트를 올리지 않는다
        #expect(boundary.logicalDay(ofStored: task.scheduledDate!) == midnight(2026, 7, 22))
    }

    // 상세 뷰 액션바 '백로그로' 경로(MainTaskDetailView)가 인라인 scheduledDate=nil이 아니라
    // 이 헬퍼로 위임함을 잠근다. ↺n 배지가 붙은 이월 태스크를 상세 뷰에서 백로그로 보낸 뒤
    // 다시 '오늘로' 가져와도 ↺ 배지가 뜨지 않아야 한다 (§13.3, 세 번째 쓰기 지점).
    @Test("상세 뷰 '백로그로' 경로도 rolloverCount를 리셋한다 (§13.3)")
    func detailViewBacklogPathResetsRolloverCount() {
        let task = TodoTask(title: "상세 뷰 이월", scheduledDate: boundary.scheduledToday(), rolloverCount: 5)
        store.addTask(task)

        // 상세 뷰 액션바 '백로그로' 버튼이 호출하는 것과 동일한 헬퍼.
        RowAction.moveToBacklog(task, store: store)
        #expect(task.scheduledDate == nil)
        #expect(task.rolloverCount == 0)

        RowAction.moveToToday(task, store: store, boundary: boundary)
        #expect(task.rolloverCount == 0)  // 상세 뷰 왕복 후에도 ↺ 배지 없음
    }

    // 네 번째 쓰기 지점: 행 날짜 팝오버(DueDateControls)의 '지우기' 칩.
    // MainTaskRow.scheduledDateBinding setter가 nil을 받으면 이 헬퍼로 위임해야 한다.
    // 수정 전엔 setter가 scheduledDate만 nil로 두어 rolloverCount가 남았고,
    // 백로그 뷰에 ↺n이 뜨고 이후 '오늘로' 가져와도 ↺n이 유지되던 누수를 잠근다 (§13.3).
    @Test("날짜 팝오버 '지우기' 경로도 rolloverCount를 리셋한다 (§13.3)")
    func datePopoverClearPathResetsRolloverCount() {
        let task = TodoTask(title: "팝오버 지우기", scheduledDate: boundary.scheduledToday(), rolloverCount: 2)
        store.addTask(task)

        // 팝오버 '지우기' = scheduledDateBinding setter에 nil 전달 → RowAction.moveToBacklog 위임.
        RowAction.moveToBacklog(task, store: store)
        #expect(task.scheduledDate == nil)
        #expect(task.rolloverCount == 0)  // 백로그 뷰에 ↺ 배지 없음
        #expect(store.backlogTasks().map(\.id) == [task.id])

        RowAction.moveToToday(task, store: store, boundary: boundary)
        #expect(task.rolloverCount == 0)  // 오늘로 가져와도 ↺ 배지 없음
    }

    // §22.1 회귀 잠금 — 백로그 이동은 bucket=.backlog·somedayOrigin=false로 정규화한다.
    // 재현: '언젠가' → [오늘 하기](pullToToday: bucket=active·오늘·somedayOrigin=true)
    //       → 해야할일에서 '백로그로'(RowAction.moveToBacklog).
    // 수정 전엔 moveToBacklog가 bucket/somedayOrigin을 안 건드려 bucket=.active·somedayOrigin=true가 남아
    // 무일정 백로그 항목에 '여유' 배지(MainSomedayBadge: somedayOrigin && bucket != .someday)가 잘못 붙고
    // '언젠가로 되돌리기' 메뉴가 노출됐다. bucket 불변식(Models §22.1: 백로그=일정 nil & bucket=.backlog)도 위반됐다.
    @Test("someday→오늘→백로그는 bucket=.backlog·somedayOrigin=false로 정규화한다 (§22.1)")
    func somedayPullThenBacklogNormalizes() {
        let task = TodoTask(title: "언젠가 왕복", bucket: .someday)
        store.addTask(task)
        store.pullToToday(task, boundary: boundary)
        #expect(task.somedayOrigin)          // pull이 출신을 기억
        #expect(task.bucket == .active)

        RowAction.moveToBacklog(task, store: store)
        #expect(task.scheduledDate == nil)
        #expect(task.bucket == .backlog)     // active 잔존 아님 — 불변식 회복
        #expect(!task.somedayOrigin)         // '여유' 배지·되돌리기 메뉴 조건 소멸
        #expect(store.backlogTasks().map(\.id) == [task.id])  // 백로그에 정상 소속
        #expect(store.somedayTasks().isEmpty)
    }

    // §22.3 회귀 잠금 — 백로그로 이탈한 항목은 이후 오늘로 예약해 미완료로 둬도
    // 다음 하루 경계 returnOverdueSomedayTasks에 잡혀 '언젠가'로 튀지 않는다.
    // 수정 전 sticky somedayOrigin=true 때문에 사용자가 명시적으로 백로그로 옮긴 항목이 someday로 조용히 복귀했다.
    @Test("someday→오늘→백로그 후 오늘 예약 항목은 경계에서 언젠가로 복귀하지 않는다 (§22.3)")
    func backlogItemNotReturnedToSomedayAtBoundary() {
        let task = TodoTask(title: "명시 백로그", bucket: .someday)
        store.addTask(task)
        store.pullToToday(task, boundary: boundary)
        RowAction.moveToBacklog(task, store: store)          // bucket=.backlog·somedayOrigin=false 확정
        RowAction.moveToToday(task, store: store, boundary: boundary)  // 7/22(오늘)로 예약, 미완료
        #expect(!task.somedayOrigin)

        // 다음 하루 경계(7/23)에서 7/22 일정은 과거가 된다 — origin이면 언젠가로 복귀했을 지점.
        let nextDay = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 23, 10, 0) })
        let rollover = RolloverService(store: store, dayBoundary: nextDay)
        rollover.returnOverdueSomedayTasks()

        #expect(task.bucket != .someday)     // 언젠가로 튀지 않음
        #expect(task.isActive)
        #expect(store.somedayTasks().isEmpty)
        // 일반 이월 경로에는 정상적으로 과거 미완료로 남는다(overdue 취급).
        #expect(rollover.unfinishedTasksFromPreviousDays().map(\.id) == [task.id])
    }
}

// §20.2 회귀 잠금 — 되돌리기(RowAction.reactivate) 경로의 주간 목표 카운트 보정.
// 완료 취소(-1) 규약이 유예 컨트롤러·브리핑 경로에만 있고 기존 행 UX의 되돌리기 2곳
// (완료 뷰 우클릭 컨텍스트 메뉴·상세 뷰 액션바 버튼)이 우회하던 회귀를 막는다.
// 두 UI 경로 모두 RowAction.reactivate로 수렴하므로 이 헬퍼 하나를 잠그면 둘 다 잠긴다.
@MainActor
@Suite("행 액션 헬퍼 — 되돌리기 주간 목표 -1")
struct RowActionReactivateGoalTests {
    private let store: JSONTaskStore
    private let boundary: DayBoundaryService
    // 전역 컨테이너(.shared) 대신 지역 컨트롤러 주입 — 테스트 격리(실 store.json 비접근).
    private let grace: CompletionGraceController

    init() {
        store = makeTempStore()
        boundary = DayBoundaryService(
            settings: makeTestSettings(boundaryHour: 6), now: { date(2026, 8, 4, 12, 0) })
        grace = CompletionGraceController(
            store: store, dayBoundary: boundary,
            recurrence: RecurrenceService(store: store, dayBoundary: boundary),
            graceInterval: 60)
    }

    private func addGoal(target: Int = 3) -> WeeklyGoal {
        let goal = WeeklyGoal(
            title: "코테 3문제", targetCount: target,
            weekKey: boundary.scheduledDateValue(for: boundary.currentWeekStart()))
        store.addWeeklyGoal(goal)
        return goal
    }

    // 재현: [오늘 하기] 연결 task 완료 확정(+1, 1/3) → 되돌리기 → 다시 완료 확정.
    // 수정 전엔 되돌리기가 -1을 빠뜨려 2/3으로 부풀었다(1회 수행이 2회 집계).
    @Test("완료 되돌리기는 연결 목표를 -1 하고, 재완료해도 이중 집계되지 않는다 (§20.2)")
    func reactivateDecrementsLinkedGoal() {
        let goal = addGoal()
        let task = store.createLinkedTask(goal: goal, boundary: boundary)

        // 완료 확정(+1) — 유예 통과/브리핑 확정 훅과 동일.
        task.markCompleted(at: boundary.now())
        store.incrementGoalCount(id: goal.id)
        #expect(goal.currentCount == 1)

        // 완료 뷰 우클릭 '되돌리기'·상세 뷰 액션바 '되돌리기'가 호출하는 단일 헬퍼.
        RowAction.reactivate(task, store: store, grace: grace)
        #expect(task.isActive)
        #expect(goal.currentCount == 0)  // 되돌리기가 +1을 보정

        // 다시 완료 확정 → 실제 1회 수행이 1회로만 집계된다(2/3 부풀림 없음).
        task.markCompleted(at: boundary.now())
        store.incrementGoalCount(id: goal.id)
        #expect(goal.currentCount == 1)
    }

    // 취소됨(cancelled)은 완료 확정 훅을 탄 적이 없어 +1된 적도 없다 —
    // 되돌리기가 이를 -1로 보정하면 오히려 카운트가 깎인다. wasCompleted 판정으로 제외됨을 잠근다.
    @Test("취소됨 되돌리기는 카운트를 건드리지 않는다 (§20.2)")
    func reactivateCancelledDoesNotDecrement() {
        let goal = addGoal()
        goal.currentCount = 2  // 다른 수행으로 이미 오른 진행
        let task = store.createLinkedTask(goal: goal, boundary: boundary)
        task.markCancelled(at: boundary.now())

        RowAction.reactivate(task, store: store, grace: grace)
        #expect(task.isActive)
        #expect(goal.currentCount == 2)  // 취소됨은 +1된 적 없으므로 -1하지 않는다
    }

    // 교차 표면 경합 (§20.2): 유예 중(pending) task를 다른 표면(브리핑 등)이 직접 완료(+1)한 뒤
    // 사용자가 즉시 되돌리면, 남은 유예 confirm이 사용자 취소를 무시하고 재완료 + 재+1하던 경로.
    // reactivate가 유예 예약을 먼저 무효화(cancelPending)함을 잠근다.
    @Test("되돌리기는 유예 중인 완료 예약을 무효화한다 — confirm 재완료·재+1 없음 (§20.2)")
    func reactivateCancelsPendingGrace() {
        let goal = addGoal()
        let task = store.createLinkedTask(goal: goal, boundary: boundary)

        grace.toggleCompletion(of: task)          // 표면 A: 유예 시작 (60s — 아직 미확정)
        #expect(grace.isPending(task))
        task.markCompleted(at: boundary.now())    // 표면 B: 유예 우회 직접 완료 확정(+1)
        store.incrementGoalCount(id: goal.id)
        #expect(goal.currentCount == 1)

        RowAction.reactivate(task, store: store, grace: grace)  // 사용자 즉시 완료 취소
        #expect(task.isActive)
        #expect(goal.currentCount == 0)
        #expect(!grace.isPending(task))           // 유예 예약이 소거됐다

        grace.flushAll()                          // 잔존 예약이 있었다면 여기서 재완료됐을 것
        #expect(task.isActive)                    // 사용자 취소가 유지된다
        #expect(goal.currentCount == 0)           // 재+1 부풀림 없음
    }
}
