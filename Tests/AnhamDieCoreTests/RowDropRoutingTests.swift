import Foundation
import Testing
@testable import AnhamDieApp

// PLAN §12.6 회귀 잠금 — 행 드롭 라우팅(applyRowDrop):
// reorderOnly 플래그가 날짜 변경(reschedule)을 컨텍스트별로 정확히 게이팅하는지 검증한다.
// 특히 캘린더 일간 뷰/패널(reorderOnly=true)에서 scheduledDate가 조용히 바뀌던 v3 회귀를 막는다.

@MainActor
@Suite("행 드롭 라우팅 — reorderOnly 게이팅")
struct RowDropRoutingTests {
    private let store: JSONTaskStore
    private let boundary: DayBoundaryService

    private let today = midnight(2026, 7, 22)
    private let day26 = midnight(2026, 7, 26)
    private let day28 = midnight(2026, 7, 28)

    init() {
        store = makeTempStore()
        boundary = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
    }

    // 캘린더 일간 뷰가 재현하던 정확한 시나리오: 7/28 뷰에 7/28-scheduled 태스크와
    // 7/26-scheduled·7/28-due(스패닝) 태스크가 함께 보인다. 둘은 다른 그룹이라
    // reorderOnly가 없으면 드롭이 scheduledDate를 7/26으로 조용히 바꿔버린다.
    @Test("reorderOnly=true면 다른 그룹 행 위 드롭도 scheduledDate 불변")
    func reorderOnlyNeverReschedules() {
        let source = TodoTask(title: "7/28 예정", scheduledDate: day28)
        let target = TodoTask(title: "7/26 예정·7/28 마감", scheduledDate: day26, dueDate: day28)
        store.addTask(source)
        store.addTask(target)

        applyRowDrop(
            sourceID: source.id, targetID: target.id, placeBefore: true,
            reorderOnly: true, store: store, boundary: boundary
        )

        #expect(source.scheduledDate == day28)  // 캘린더/오버레이 안전: 날짜 불변
    }

    @Test("reorderOnly=false(해야할 일) + 다른 그룹이면 대상 그룹 날짜로 reschedule")
    func scheduleListReschedulesAcrossGroups() {
        let source = TodoTask(title: "오늘", scheduledDate: today)
        let target = TodoTask(title: "7/28 예정", scheduledDate: day28)
        store.addTask(source)
        store.addTask(target)

        applyRowDrop(
            sourceID: source.id, targetID: target.id, placeBefore: true,
            reorderOnly: false, store: store, boundary: boundary
        )

        #expect(source.scheduledDate == day28)  // 의도된 날짜 변경
    }

    @Test("reorderOnly=false + 같은 그룹이면 scheduledDate 불변(수동 정렬만)")
    func sameGroupKeepsDate() {
        let source = TodoTask(title: "오늘 A", scheduledDate: today)
        let target = TodoTask(title: "오늘 B", scheduledDate: today)
        store.addTask(source)
        store.addTask(target)

        applyRowDrop(
            sourceID: source.id, targetID: target.id, placeBefore: false,
            reorderOnly: false, store: store, boundary: boundary
        )

        #expect(source.scheduledDate == today)
    }

    @Test("reorderOnly=false여도 완료(비활성) 소스는 reschedule 안 함")
    func completedSourceNeverReschedules() {
        let source = TodoTask(title: "완료됨", scheduledDate: today)
        source.markCompleted(at: date(2026, 7, 22, 9, 0))
        let target = TodoTask(title: "7/28 예정", scheduledDate: day28)
        store.addTask(source)
        store.addTask(target)

        applyRowDrop(
            sourceID: source.id, targetID: target.id, placeBefore: true,
            reorderOnly: false, store: store, boundary: boundary
        )

        #expect(source.scheduledDate == today)
    }
}
