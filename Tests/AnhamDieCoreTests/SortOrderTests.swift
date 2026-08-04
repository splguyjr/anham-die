import Foundation
import Testing
@testable import AnhamDieApp

// PLAN §11.3 — 표시 순서 단일 소스: 초기 배치 규칙, reorder API, 마이그레이션.

@MainActor
@Suite("정렬 단일화 (§11.3)")
struct SortOrderTests {
    @Test("초기 배치: 우선순위 높음 → 같으면 등록순")
    func initialPlacement() {
        let store = makeTempStore()
        let a = TodoTask(title: "A", createdAt: date(2026, 7, 20, 10), priority: .normal)
        let b = TodoTask(title: "B", createdAt: date(2026, 7, 20, 11), priority: .high)
        let c = TodoTask(title: "C", createdAt: date(2026, 7, 20, 12), priority: .low)
        let d = TodoTask(title: "D", createdAt: date(2026, 7, 20, 13), priority: .normal)
        [a, b, c, d].forEach { store.addTaskApplyingInitialOrder($0) }

        #expect(store.tasksInDisplayOrder().map(\.title) == ["B", "A", "D", "C"])
    }

    @Test("sortOrder는 0..n-1로 재부여되어 유일하다")
    func sortOrdersAreUnique() {
        let store = makeTempStore()
        for i in 0..<5 {
            store.addTaskApplyingInitialOrder(
                TodoTask(title: "T\(i)", createdAt: date(2026, 7, 20, 10 + i),
                         priority: i.isMultiple(of: 2) ? .high : .low)
            )
        }
        let orders = store.tasksInDisplayOrder().map(\.sortOrder)
        #expect(orders == [0, 1, 2, 3, 4])
    }

    @Test("reorder(before:): 대상 앞으로 이동·영속")
    func reorderBefore() {
        let store = makeTempStore()
        let tasks = (0..<4).map { TodoTask(title: "T\($0)", createdAt: date(2026, 7, 20, 10 + $0)) }
        tasks.forEach { store.addTaskApplyingInitialOrder($0) }

        store.reorderTask(id: tasks[3].id, before: tasks[1].id)
        #expect(store.tasksInDisplayOrder().map(\.title) == ["T0", "T3", "T1", "T2"])
    }

    @Test("reorder(after:): 대상 뒤로 이동")
    func reorderAfter() {
        let store = makeTempStore()
        let tasks = (0..<4).map { TodoTask(title: "T\($0)", createdAt: date(2026, 7, 20, 10 + $0)) }
        tasks.forEach { store.addTaskApplyingInitialOrder($0) }

        store.reorderTask(id: tasks[0].id, after: tasks[2].id)
        #expect(store.tasksInDisplayOrder().map(\.title) == ["T1", "T2", "T0", "T3"])
    }

    @Test("드래그 후에는 수동 순서가 우선 — 새 태스크는 '우선순위 ≥'인 마지막 뒤에 삽입")
    func manualOrderSurvivesInsertion() {
        let store = makeTempStore()
        let high = TodoTask(title: "높음", createdAt: date(2026, 7, 20, 10), priority: .high)
        let low = TodoTask(title: "낮음", createdAt: date(2026, 7, 20, 11), priority: .low)
        [high, low].forEach { store.addTaskApplyingInitialOrder($0) }
        // 수동 정렬: 낮음을 맨 앞으로
        store.reorderTask(id: low.id, before: high.id)
        #expect(store.tasksInDisplayOrder().map(\.title) == ["낮음", "높음"])

        let normal = TodoTask(title: "보통", createdAt: date(2026, 7, 20, 12), priority: .normal)
        store.addTaskApplyingInitialOrder(normal)
        // '우선순위 ≥ 보통'인 마지막(높음) 뒤 — 수동으로 앞에 둔 낮음은 그대로
        #expect(store.tasksInDisplayOrder().map(\.title) == ["낮음", "높음", "보통"])
    }

    @Test("모든 조회가 같은 순서를 쓴다 (todayTasks = scheduleSections 오늘 섹션)")
    func queriesShareOrder() {
        let settings = makeTestSettings()
        let store = makeTempStore()
        let boundary = DayBoundaryService(settings: settings, now: { date(2026, 7, 23, 14) })

        let tasks = (0..<3).map { i -> TodoTask in
            let t = TodoTask(title: "T\(i)", createdAt: date(2026, 7, 23, 10 + i))
            t.scheduledDate = boundary.scheduledToday()
            return t
        }
        tasks.forEach { store.addTaskApplyingInitialOrder($0) }
        store.reorderTask(id: tasks[2].id, before: tasks[0].id)

        let today = store.todayTasks(boundary: boundary).map(\.id)
        let sections = store.scheduleSections(boundary: boundary)
        let todaySection = sections.first { $0.day == boundary.logicalToday() }?.tasks.map(\.id)
        #expect(today == [tasks[2].id, tasks[0].id, tasks[1].id])
        #expect(todaySection == today)
    }

    @Test("마이그레이션 v1→v2: sortOrder를 우선순위→createdAt으로 재부여하고 버전을 올린다")
    func migrationReassignsSortOrder() throws {
        let dir = makeTempStoreDirectory()
        let first = JSONTaskStore(directory: dir)
        // v1 시절 규약: 추가순 max+1 (우선순위 무시)
        let low = TodoTask(title: "낮음", createdAt: date(2026, 7, 20, 10), priority: .low, sortOrder: 1)
        let high = TodoTask(title: "높음", createdAt: date(2026, 7, 20, 11), priority: .high, sortOrder: 2)
        let old = TodoTask(title: "보통-먼저", createdAt: date(2026, 7, 19, 9), priority: .normal, sortOrder: 3)
        let new = TodoTask(title: "보통-나중", createdAt: date(2026, 7, 21, 9), priority: .normal, sortOrder: 4)
        [low, high, old, new].forEach { first.addTask($0) }
        first.saveNow()

        // 디스크 문서를 v1로 되돌린다 (현재 문서 버전은 v3 — §20.5)
        let fileURL = dir.appendingPathComponent("store.json")
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(text.contains("\"version\" : 3"))
        try text.replacingOccurrences(of: "\"version\" : 3", with: "\"version\" : 1")
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let migrated = JSONTaskStore(directory: dir)
        #expect(migrated.tasksInDisplayOrder().map(\.title) == ["높음", "보통-먼저", "보통-나중", "낮음"])
        #expect(migrated.tasksInDisplayOrder().map(\.sortOrder) == [0, 1, 2, 3])

        // 마이그레이션 직후 디스크가 현재 버전(v3)으로 확정된다
        let rewritten = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(rewritten.contains("\"version\" : 3"))
    }
}
