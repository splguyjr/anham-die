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
}
