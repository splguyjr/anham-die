import Foundation
import Testing
@testable import AnhamDieApp

// MARK: - v13 오버레이 '여유 칸' 조건 (PLAN §22.2·§22.4)
// 뷰 body에서 분리한 순수 헬퍼(TaskStore.overlaySomedayItems / isEmphasized)를 검증한다:
// 설정 on/off 게이팅, prefix(count) 선택, 오늘 미완료 0(전부 완료·오늘 없음) 강조.

@MainActor
@Suite("오버레이 여유 칸 선택 (show·count)")
struct OverlaySomedaySelectionTests {
    /// 언젠가 항목 n개를 표시 순서(sortOrder 0..n-1)대로 넣은 store.
    private func storeWithSomeday(_ count: Int) -> JSONTaskStore {
        let store = makeTempStore()
        for i in 0..<count {
            store.addTask(TodoTask(title: "언젠가 \(i)", sortOrder: i, bucket: .someday))
        }
        return store
    }

    @Test("show=false면 빈 목록 (설정 off → 섹션 없음)")
    func showFalseYieldsEmpty() {
        let store = storeWithSomeday(3)
        #expect(store.overlaySomedayItems(show: false, count: 3).isEmpty)
    }

    @Test("show=true면 표시 순서 상위 count개로 제한된다")
    func cappedAtCount() {
        let store = storeWithSomeday(5)
        let items = store.overlaySomedayItems(show: true, count: 2)
        #expect(items.count == 2)
        #expect(items.map(\.title) == ["언젠가 0", "언젠가 1"])
    }

    @Test("항목이 count보다 적으면 있는 만큼만 (초과 요청 무해)")
    func fewerThanCount() {
        let store = storeWithSomeday(2)
        #expect(store.overlaySomedayItems(show: true, count: 5).count == 2)
    }

    @Test("count≤0이면 빈 목록 (음수·0 방어)")
    func zeroOrNegativeCount() {
        let store = storeWithSomeday(3)
        #expect(store.overlaySomedayItems(show: true, count: 0).isEmpty)
        #expect(store.overlaySomedayItems(show: true, count: -1).isEmpty)
    }

    @Test("완료된 someday는 선택에서 빠진다 (somedayTasks 미완료 조건 상속)")
    func completedSomedayExcluded() {
        let store = makeTempStore()
        let active = TodoTask(title: "미완료", sortOrder: 0, bucket: .someday)
        let done = TodoTask(title: "완료", sortOrder: 1, bucket: .someday)
        done.markCompleted(at: date(2026, 7, 22, 12, 0))
        store.addTask(active)
        store.addTask(done)
        #expect(store.overlaySomedayItems(show: true, count: 5).map(\.id) == [active.id])
    }
}

@MainActor
@Suite("오버레이 여유 칸 강조 (오늘 미완료 0)")
struct OverlaySomedayEmphasisTests {
    private func todo(_ title: String, done: Bool = false) -> TodoTask {
        let t = TodoTask(title: title)
        if done { t.markCompleted(at: date(2026, 7, 22, 12, 0)) }
        return t
    }

    @Test("오늘 항목이 모두 완료면 강조한다")
    func allDoneEmphasized() {
        let store = makeTempStore()
        let today = [todo("a", done: true), todo("b", done: true)]
        #expect(store.isEmphasized(today: today) { $0.isCompleted })
    }

    @Test("오늘 항목이 0개면 강조한다 (여유 있음)")
    func emptyTodayEmphasized() {
        let store = makeTempStore()
        #expect(store.isEmphasized(today: []) { $0.isCompleted })
    }

    @Test("오늘 미완료가 하나라도 있으면 강조하지 않는다")
    func incompleteNotEmphasized() {
        let store = makeTempStore()
        let today = [todo("a", done: true), todo("b", done: false)]
        #expect(!store.isEmphasized(today: today) { $0.isCompleted })
    }

    @Test("완료 유예(pending)도 완료로 넘기면 강조된다 (오버레이 체크 표시와 일치)")
    func pendingCountsAsDone() {
        let store = makeTempStore()
        let a = todo("a", done: true)
        let b = todo("b", done: false) // 아직 완료 아님 — 유예 중이라고 가정
        let pending: Set<UUID> = [b.id]
        #expect(store.isEmphasized(today: [a, b]) { $0.isCompleted || pending.contains($0.id) })
        // 유예 반영을 빼면 미완료가 남아 강조되지 않는다 — pending이 강조 시점을 앞당김을 확인
        #expect(!store.isEmphasized(today: [a, b]) { $0.isCompleted })
    }
}
