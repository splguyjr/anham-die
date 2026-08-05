import Foundation
import Testing
@testable import AnhamDieApp

// MARK: - scheduledDate 저장 규약 회귀 테스트

@MainActor
@Suite("scheduledDate 저장 규약")
struct ScheduledDateConventionTests {
    private let store: JSONTaskStore
    private let boundary: DayBoundaryService

    init() {
        store = makeTempStore()
        boundary = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
    }

    @Test("scheduledToday()로 저장한 태스크는 todayTasks에 나타난다")
    func canonicalValueAppearsInToday() {
        let task = TodoTask(title: "오늘 것", scheduledDate: boundary.scheduledToday())
        store.addTask(task)
        #expect(store.todayTasks(boundary: boundary).map(\.id) == [task.id])
        // 이월 제안(이전 하루 미완료)에 잘못 등장하지 않아야 한다
        let rollover = RolloverService(store: store, dayBoundary: boundary)
        #expect(rollover.unfinishedTasksFromPreviousDays().isEmpty)
    }

    @Test("규약 값은 logicalDay(ofStored:) 해석 시 같은 논리적 날짜다")
    func canonicalValueRoundTrips() {
        let day = midnight(2026, 7, 22)
        let stored = boundary.scheduledDateValue(for: day)
        #expect(boundary.logicalDay(ofStored: stored) == day)
    }

    @Test("과거 규약 값(자정+당시 오프셋)도 같은 날짜로 해석된다 — 마이그레이션 불필요")
    func legacyStoredValueResolvesToSameDay() {
        #expect(boundary.logicalDay(ofStored: date(2026, 7, 22, 9, 0)) == midnight(2026, 7, 22))
        #expect(boundary.logicalDay(ofStored: date(2026, 7, 22, 23, 59)) == midnight(2026, 7, 22))
    }

    @Test("경계 시각을 9→10으로 바꿔도 오늘 태스크가 유지된다")
    func boundaryChangeKeepsTodayTasks() {
        let settings = makeTestSettings()
        let boundary = DayBoundaryService(settings: settings, now: { date(2026, 7, 22, 10, 30) })
        let task = TodoTask(title: "새 규약 값", scheduledDate: boundary.scheduledToday())
        // 경계 09:00 시절 과거 규약(자정+9h)으로 저장된 기존 데이터
        let legacy = TodoTask(title: "과거 규약 값", scheduledDate: date(2026, 7, 22, 9, 0))
        store.addTask(task)
        store.addTask(legacy)
        let rollover = RolloverService(store: store, dayBoundary: boundary)
        #expect(store.todayTasks(boundary: boundary).count == 2)

        settings.dayBoundaryHour = 10

        #expect(Set(store.todayTasks(boundary: boundary).map(\.id)) == [task.id, legacy.id])
        // 전날로 밀려 이월 제안(rolloverCount 부당 증가 경로)에 등장하지 않아야 한다
        #expect(rollover.unfinishedTasksFromPreviousDays().isEmpty)
    }
}

// MARK: - 완료 항목 표시 규칙 회귀 테스트 (PLAN §7: 당일 취소선 → 다음 논리적 하루에 숨김)

@MainActor
@Suite("완료된 due-only 항목의 오늘 목록 포함")
struct CompletedDueTaskVisibilityTests {
    private let store: JSONTaskStore
    private let boundary: DayBoundaryService

    init() {
        store = makeTempStore()
        boundary = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
    }

    @Test("due가 오늘인 항목은 완료 직후에도 오늘 목록에 남는다")
    func completedDueOnlyTaskStaysInTodayList() {
        let task = TodoTask(title: "예정 탭에서 추가", dueDate: date(2026, 7, 22, 10, 0))
        store.addTask(task)
        #expect(store.todayTasks(boundary: boundary).map(\.id) == [task.id])

        task.markCompleted(at: date(2026, 7, 22, 11, 0))
        #expect(store.todayTasks(boundary: boundary).map(\.id) == [task.id])
    }

    @Test("완료된 due-only 항목은 다음 논리적 하루부터 숨겨진다")
    func completedDueOnlyTaskHiddenNextLogicalDay() {
        let task = TodoTask(title: "어제 완료한 것", dueDate: date(2026, 7, 22, 10, 0))
        task.markCompleted(at: date(2026, 7, 22, 11, 0))
        store.addTask(task)

        let nextDay = DayBoundaryService(
            settings: makeTestSettings(), now: { date(2026, 7, 23, 10, 0) })
        #expect(store.todayTasks(boundary: nextDay).isEmpty)
        // 완료 당일(7/22)의 목록에는 여전히 포함된다
        #expect(store.tasks(on: midnight(2026, 7, 22), boundary: nextDay).map(\.id) == [task.id])
    }

    @Test("취소된 due 항목은 당일 목록에서도 제외된다")
    func cancelledDueTaskExcluded() {
        let task = TodoTask(title: "버린 것", dueDate: date(2026, 7, 22, 10, 0))
        task.markCancelled(at: date(2026, 7, 22, 11, 0))
        store.addTask(task)
        #expect(store.todayTasks(boundary: boundary).isEmpty)
    }

    @Test("완료돼도 오늘 목록에 남아 진행률 분모가 유지된다")
    func progressDenominatorStable() {
        let done = TodoTask(title: "완료할 것", dueDate: date(2026, 7, 22, 10, 0))
        let open = TodoTask(title: "남은 것", scheduledDate: boundary.scheduledToday())
        store.addTask(done)
        store.addTask(open)

        let before = store.todayTasks(boundary: boundary)
        #expect(before.count == 2)

        done.markCompleted(at: date(2026, 7, 22, 11, 0))
        let after = store.todayTasks(boundary: boundary)
        #expect(after.count == 2)
        #expect(after.filter(\.isCompleted).count == 1)
    }
}

// MARK: - 저장소 손상/버전 보호

@MainActor
@Suite("JSONTaskStore 데이터 보호")
struct TaskStoreProtectionTests {
    @Test("디코드 실패 시 원본을 .corrupt 백업으로 보존한다")
    func corruptFileIsBackedUp() throws {
        let dir = makeTempStoreDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("store.json")
        let corruptContent = #"{"version":1,"tasks":[{"ttl":"broken"}],"tags":[]}"#
        try corruptContent.write(to: file, atomically: true, encoding: .utf8)

        let store = JSONTaskStore(directory: dir)
        #expect(store.tasks.isEmpty)

        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("store.json.corrupt-") }
        #expect(backups.count == 1)
        let backupContent = try String(
            contentsOf: dir.appendingPathComponent(backups[0]), encoding: .utf8)
        #expect(backupContent == corruptContent)

        // 이후 저장이 백업을 건드리지 않는다
        store.addTask(TodoTask(title: "새 태스크"))
        store.saveNow()
        let backupsAfter = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("store.json.corrupt-") }
        #expect(backupsAfter == backups)
    }

    @Test("디스크 문서 버전이 더 높으면 쓰기를 거부한다")
    func newerVersionBlocksSave() throws {
        let dir = makeTempStoreDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("store.json")
        let newerContent = #"{"version":999,"tasks":[],"tags":[]}"#
        try newerContent.write(to: file, atomically: true, encoding: .utf8)

        let store = JSONTaskStore(directory: dir)
        #expect(store.saveBlocked)
        store.addTask(TodoTask(title: "저장되면 안 됨"))
        store.saveNow()

        let onDisk = try String(contentsOf: file, encoding: .utf8)
        #expect(onDisk == newerContent)
    }

    @Test("정상 문서는 저장/재로드 왕복이 된다")
    func roundTrip() throws {
        let dir = makeTempStoreDirectory()
        let store = JSONTaskStore(directory: dir)
        let task = TodoTask(title: "왕복", scheduledDate: date(2026, 7, 22, 9, 0))
        task.rolloverCount = 2
        store.addTask(task)
        store.saveNow()

        let reloaded = JSONTaskStore(directory: dir)
        #expect(reloaded.tasks.count == 1)
        #expect(reloaded.tasks[0].title == "왕복")
        #expect(reloaded.tasks[0].rolloverCount == 2)
        #expect(reloaded.tasks[0].scheduledDate != nil)
    }

    @Test("mergeFromDisk는 상태 필드만 갱신하고 메모리 변경을 보존한다")
    func mergeFromDiskPreservesMemory() throws {
        let dir = makeTempStoreDirectory()
        let store = JSONTaskStore(directory: dir)
        let a = TodoTask(title: "A")
        store.addTask(a)
        store.saveNow()

        // 다른 프로세스(위젯) 역할: 같은 파일을 열어 A를 완료 처리
        let other = JSONTaskStore(directory: dir)
        other.task(withID: a.id)?.markCompleted(at: date(2026, 7, 22, 11, 0))
        other.saveNow()

        // 앱 메모리에는 아직 저장 안 된 새 태스크 B가 있다
        let b = TodoTask(title: "B")
        store.addTask(b)

        store.mergeFromDisk()
        #expect(store.task(withID: a.id)?.isCompleted == true)
        #expect(store.task(withID: b.id) != nil)
    }

    @Test("mergeFromDisk는 디스크 미변경(no-op 알림) 시 메모리 전용 변경을 덮어쓰지 않는다")
    func mergeFromDiskSkipsWhenDiskUnchanged() throws {
        let dir = makeTempStoreDirectory()
        let store = JSONTaskStore(directory: dir)
        let a = TodoTask(title: "A")
        store.addTask(a)
        store.saveNow() // 디스크: A active, mtime 기록

        // 앱이 메모리에서만 A를 완료 처리(아직 저장하지 않음)
        store.task(withID: a.id)?.markCompleted(at: date(2026, 7, 22, 11, 0))

        // 디스크가 그대로인데 위젯 Darwin 알림이 옴 → mtime 동일이라 디코드/머지를 건너뛰어
        // 메모리 변경을 보존한다. (스킵 없이 무조건 머지하면 disk의 active로 되돌아간다.)
        store.mergeFromDisk()
        #expect(store.task(withID: a.id)?.isCompleted == true)
    }

    @Test("mergeFromDisk는 위젯이 올린 주간 목표 카운트를 채택하고 이후 앱 저장에서 보존한다")
    func mergeFromDiskAdoptsWidgetGoalCount() throws {
        let dir = makeTempStoreDirectory()
        let store = JSONTaskStore(directory: dir)
        let goal = WeeklyGoal(title: "물 마시기", targetCount: 5, weekKey: midnight(2026, 7, 20))
        store.addWeeklyGoal(goal)
        store.saveNow() // 디스크: currentCount 0

        // 위젯 역할: 같은 파일을 열어 목표 +1 후 즉시 플러시 (§20.2 완료 훅과 동일 경로)
        let widget = JSONTaskStore(directory: dir)
        widget.incrementGoalCount(id: goal.id)
        widget.saveNow()

        // 머지 전 앱 메모리 카운트는 스테일 0
        #expect(store.weeklyGoal(withID: goal.id)?.currentCount == 0)

        // Darwin 알림 → 앱이 재읽기하면 위젯의 +1을 채택한다
        store.mergeFromDisk()
        #expect(store.weeklyGoal(withID: goal.id)?.currentCount == 1)

        // 이후 앱이 아무 변경(무관한 새 태스크)으로든 저장해도 위젯 +1이 디스크에 남는다(lost update 없음)
        store.addTask(TodoTask(title: "무관한 새 태스크"))
        store.saveNow()
        let reloaded = JSONTaskStore(directory: dir)
        #expect(reloaded.weeklyGoal(withID: goal.id)?.currentCount == 1)
    }

    @Test("mergeFromDisk는 메모리에 없는 위젯 생성 목표를 흡수한다")
    func mergeFromDiskAppendsUnknownGoal() throws {
        let dir = makeTempStoreDirectory()
        let store = JSONTaskStore(directory: dir)
        store.addTask(TodoTask(title: "앵커")) // 디스크에 초기 문서를 만들어 mtime 기록
        store.saveNow()

        let widget = JSONTaskStore(directory: dir)
        let goal = WeeklyGoal(title: "새 목표", weekKey: midnight(2026, 7, 20))
        widget.addWeeklyGoal(goal)
        widget.saveNow()

        #expect(store.weeklyGoal(withID: goal.id) == nil)
        store.mergeFromDisk()
        #expect(store.weeklyGoal(withID: goal.id) != nil)
    }

    @Test("v1 문서(앱 v2 설치본 형식) 로드 — 데이터 보존 + 현재 버전으로 상승, recurrence 기본값")
    func migratesHandwrittenV1Document() throws {
        // 앱 v2 설치본이 실제로 쓰던 형식 그대로: version 1, iso8601 날짜,
        // recurrence/recurrenceSeriesID 키 없음.
        let dir = makeTempStoreDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("store.json")
        let v1Content = """
        {
          "version" : 1,
          "tags" : [
            { "colorHex" : "#FF3B30", "id" : "AAAAAAAA-0000-0000-0000-000000000001", "name" : "업무" }
          ],
          "tasks" : [
            {
              "createdAt" : "2026-07-20T01:00:00Z",
              "id" : "BBBBBBBB-0000-0000-0000-000000000001",
              "note" : "메모 내용",
              "priority" : 2,
              "rolloverCount" : 1,
              "scheduledDate" : "2026-07-21T15:00:00Z",
              "dueDate" : "2026-07-22T15:00:00Z",
              "sortOrder" : 5,
              "status" : "active",
              "subtasks" : [
                { "id" : "CCCCCCCC-0000-0000-0000-000000000001", "isDone" : true, "sortOrder" : 0, "title" : "하위 1" }
              ],
              "tagIDs" : [ "AAAAAAAA-0000-0000-0000-000000000001" ],
              "title" : "이월된 업무"
            },
            {
              "completedAt" : "2026-07-20T05:00:00Z",
              "createdAt" : "2026-07-19T23:00:00Z",
              "id" : "BBBBBBBB-0000-0000-0000-000000000002",
              "note" : "",
              "priority" : 1,
              "rolloverCount" : 0,
              "sortOrder" : 3,
              "status" : "completed",
              "subtasks" : [],
              "tagIDs" : [],
              "title" : "끝난 일"
            }
          ]
        }
        """
        try v1Content.write(to: file, atomically: true, encoding: .utf8)

        let store = JSONTaskStore(directory: dir)
        #expect(!store.saveBlocked)
        #expect(store.tasks.count == 2)
        #expect(store.tags.count == 1)
        #expect(store.tags[0].name == "업무")

        let carried = try #require(store.task(
            withID: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!))
        #expect(carried.title == "이월된 업무")
        #expect(carried.note == "메모 내용")
        #expect(carried.priority == .high)
        #expect(carried.rolloverCount == 1)
        #expect(carried.scheduledDate != nil)
        #expect(carried.dueDate != nil)
        #expect(carried.tagIDs == [store.tags[0].id])
        #expect(carried.subtasks.count == 1)
        #expect(carried.subtasks[0].isDone)
        // 구버전 문서에 없던 필드는 기본값으로 흡수된다 (§11.5)
        #expect(carried.recurrence == RecurrenceRule.none)
        #expect(carried.recurrenceSeriesID == nil)

        let done = try #require(store.task(
            withID: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!))
        #expect(done.isCompleted)
        #expect(done.completedAt != nil)

        // 마이그레이션 직후 디스크 문서가 현재 버전(v4, §22.1)으로 확정되고 recurrence 키가 기록된다
        let rewritten = try String(contentsOf: file, encoding: .utf8)
        #expect(rewritten.contains("\"version\" : 4"))
        #expect(rewritten.contains("\"recurrence\""))
        // sortOrder는 §11.3 초기 배치 규칙(우선순위 → createdAt)으로 재부여된다
        #expect(store.tasksInDisplayOrder().map(\.title) == ["이월된 업무", "끝난 일"])
    }
}
