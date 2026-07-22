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

    @Test("규약 값은 logicalDate 재해석 시 같은 논리적 날짜다")
    func canonicalValueRoundTrips() {
        let day = midnight(2026, 7, 22)
        let stored = boundary.scheduledDateValue(for: day)
        #expect(boundary.logicalDate(of: stored) == day)
    }

    @Test("자정 Date를 그대로 저장하면 전날로 재해석된다 — 규약 위반 감지용")
    func midnightValueIsPreviousDay() {
        // 이 동작 때문에 모든 쓰기 경로가 scheduledDateValue(for:)를 써야 한다
        #expect(boundary.logicalDate(of: midnight(2026, 7, 22)) == midnight(2026, 7, 21))
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
