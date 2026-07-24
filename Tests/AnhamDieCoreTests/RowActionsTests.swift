import Foundation
import Testing
@testable import AnhamDieApp

// §13.3 회귀 잠금 — UI 행 액션 헬퍼(RowAction) 경로:
// 우클릭 '백로그로'(RowAction.moveToBacklog)가 RolloverService.moveToBacklog와 동일하게
// rolloverCount를 0으로 리셋해 백로그 불변식(백로그 항목엔 ↺ 배지 없음)을 지키는지 검증한다.
// 브리핑 경로(RolloverServiceTests)와 별개로 UI 경로에서 이월 이력이 새어나가던 회귀를 막는다.

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
}
