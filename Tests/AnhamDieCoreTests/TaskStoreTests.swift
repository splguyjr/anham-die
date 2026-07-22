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
}
