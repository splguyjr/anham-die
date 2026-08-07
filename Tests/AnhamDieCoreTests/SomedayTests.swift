import Foundation
import Testing
@testable import AnhamDieApp

// MARK: - v13 '언젠가'(someday) 버킷 · 왕복 · 경계 복귀 (PLAN §22)

@MainActor
@Suite("bucket 마이그레이션 (v3 → v4)")
struct BucketMigrationTests {
    /// v3 문서(bucket 키 없음)를 직접 써 두고 로드 시 마이그레이션을 검증한다.
    private func writeV3Document(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("store.json")
        let v3 = """
        {
          "version" : 3,
          "tags" : [],
          "weeklyGoals" : [],
          "tasks" : [
            {
              "createdAt" : "2026-07-20T01:00:00Z",
              "id" : "AAAAAAAA-0000-0000-0000-000000000001",
              "note" : "",
              "priority" : 1,
              "rolloverCount" : 0,
              "sortOrder" : 0,
              "status" : "active",
              "subtasks" : [],
              "tagIDs" : [],
              "title" : "날짜 없는 미완료"
            },
            {
              "createdAt" : "2026-07-20T01:00:00Z",
              "id" : "AAAAAAAA-0000-0000-0000-000000000002",
              "note" : "",
              "priority" : 1,
              "rolloverCount" : 0,
              "scheduledDate" : "2026-07-21T15:00:00Z",
              "sortOrder" : 1,
              "status" : "active",
              "subtasks" : [],
              "tagIDs" : [],
              "title" : "일정 있는 미완료"
            },
            {
              "completedAt" : "2026-07-20T05:00:00Z",
              "createdAt" : "2026-07-19T23:00:00Z",
              "id" : "AAAAAAAA-0000-0000-0000-000000000003",
              "note" : "",
              "priority" : 1,
              "rolloverCount" : 0,
              "sortOrder" : 2,
              "status" : "completed",
              "subtasks" : [],
              "tagIDs" : [],
              "title" : "날짜 없는 완료"
            }
          ]
        }
        """
        try v3.write(to: file, atomically: true, encoding: .utf8)
    }

    @Test("기존 nil-일정 미완료는 backlog 버킷으로 승격된다")
    func nilScheduledActiveBecomesBacklog() throws {
        let dir = makeTempStoreDirectory()
        try writeV3Document(to: dir)
        let store = JSONTaskStore(directory: dir)

        let nilActive = try #require(store.task(
            withID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!))
        #expect(nilActive.bucket == .backlog)
        #expect(store.backlogTasks().map(\.id) == [nilActive.id])
    }

    @Test("일정 있는 미완료·완료 항목은 active 버킷(기본)을 유지한다")
    func scheduledAndCompletedStayActive() throws {
        let dir = makeTempStoreDirectory()
        try writeV3Document(to: dir)
        let store = JSONTaskStore(directory: dir)

        let scheduled = try #require(store.task(
            withID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!))
        let completed = try #require(store.task(
            withID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000003")!))
        #expect(scheduled.bucket == .active)
        #expect(completed.bucket == .active)
        // 마이그레이션은 백로그 집합을 늘리지 않는다 — 일정 있는·완료 항목은 backlogTasks에 없음
        #expect(!store.backlogTasks().contains { $0.id == scheduled.id })
        #expect(!store.backlogTasks().contains { $0.id == completed.id })
    }

    @Test("마이그레이션 직후 디스크가 v4로 확정되고 bucket 키가 기록된다")
    func documentUpgradedToV4() throws {
        let dir = makeTempStoreDirectory()
        try writeV3Document(to: dir)
        _ = JSONTaskStore(directory: dir)

        let rewritten = try String(
            contentsOf: dir.appendingPathComponent("store.json"), encoding: .utf8)
        #expect(rewritten.contains("\"version\" : 4"))
        #expect(rewritten.contains("\"bucket\""))
    }
}

@MainActor
@Suite("someday ↔ 오늘 왕복")
struct SomedayRoundTripTests {
    private let store: JSONTaskStore
    private let boundary: DayBoundaryService

    init() {
        store = makeTempStore()
        boundary = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
    }

    @Test("pullToToday: 오늘 task로 꺼내고 origin을 기억한다")
    func pullToTodaySetsFields() {
        let task = TodoTask(title: "언젠가 항목", bucket: .someday)
        store.addTask(task)
        #expect(store.somedayTasks().map(\.id) == [task.id])

        store.pullToToday(task, boundary: boundary)
        #expect(task.bucket == .active)
        #expect(task.somedayOrigin)
        #expect(task.scheduledDate != nil)
        #expect(store.todayTasks(boundary: boundary).map(\.id) == [task.id])
        // 더 이상 '언젠가' 목록엔 없다
        #expect(store.somedayTasks().isEmpty)
    }

    @Test("returnToSomeday: 언젠가로 되돌리고 origin 유지·rolloverCount 불변")
    func returnToSomedayKeepsOrigin() {
        let task = TodoTask(title: "왕복", bucket: .someday)
        store.addTask(task)
        store.pullToToday(task, boundary: boundary)
        let countAfterPull = task.rolloverCount

        store.returnToSomeday(task)
        #expect(task.bucket == .someday)
        #expect(task.scheduledDate == nil)
        #expect(task.somedayOrigin) // 유지
        #expect(task.rolloverCount == countAfterPull) // 불변
        #expect(store.somedayTasks().map(\.id) == [task.id])
        #expect(store.todayTasks(boundary: boundary).isEmpty)
    }

    @Test("someday 왕복은 이월 카운트를 올리지 않는다")
    func roundTripDoesNotIncrementRollover() {
        let task = TodoTask(title: "왕복 반복", bucket: .someday)
        store.addTask(task)
        store.pullToToday(task, boundary: boundary)
        store.returnToSomeday(task)
        store.pullToToday(task, boundary: boundary)
        #expect(task.rolloverCount == 0)
    }

    // 일반 오늘 task(someday 출신 아님)를 '언젠가'로 보낸다 — 네이티브 이동.
    @Test("RowAction.moveToSomeday: 일정·이월 이력 초기화하고 someday로 (origin 아님)")
    func moveToSomedayFromToday() {
        let task = TodoTask(title: "오늘 일반", scheduledDate: boundary.scheduledToday(), rolloverCount: 2)
        store.addTask(task)

        RowAction.moveToSomeday(task, store: store)

        #expect(task.bucket == .someday)
        #expect(task.scheduledDate == nil)
        #expect(task.rolloverCount == 0)     // '미룬 날' 없음 — 백로그와 동일 초기화
        #expect(!task.somedayOrigin)          // 네이티브 소속 (왕복 아님)
        #expect(store.somedayTasks().map(\.id) == [task.id])
        #expect(store.todayTasks(boundary: boundary).isEmpty)
    }

    // someday에서 꺼낸(origin) 항목을 '언젠가로'로 보내면 왕복 복귀 경로로 분기(이력 보존).
    @Test("RowAction.moveToSomeday: origin 항목은 returnToSomeday로 분기(origin 유지)")
    func moveToSomedayRoutesOriginBack() {
        let task = TodoTask(title: "왕복 항목", bucket: .someday)
        store.addTask(task)
        store.pullToToday(task, boundary: boundary)   // somedayOrigin=true

        RowAction.moveToSomeday(task, store: store)

        #expect(task.bucket == .someday)
        #expect(task.somedayOrigin)           // 왕복 이력 보존
    }
}

@MainActor
@Suite("경계 미완료 복귀 (§22.3)")
struct SomedayBoundaryReturnTests {
    @Test("origin 미완료 & 과거 일정은 언젠가로 복귀 — rolloverCount 불변")
    func overdueOriginReturnsToSomeday() {
        let store = makeTempStore()
        let today = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
        let rollover = RolloverService(store: store, dayBoundary: today)

        // 어제(7/21) 꺼냈으나 미완료로 남은 someday-origin task
        let task = TodoTask(
            title: "어제 꺼냈으나 안 함",
            scheduledDate: date(2026, 7, 21, 9, 0),
            bucket: .active,
            somedayOrigin: true
        )
        store.addTask(task)

        rollover.returnOverdueSomedayTasks()
        #expect(task.bucket == .someday)
        #expect(task.scheduledDate == nil)
        #expect(task.rolloverCount == 0) // 이월/overdue 취급 아님
        #expect(store.somedayTasks().map(\.id) == [task.id])
        // 일반 이월 후보에도 등장하지 않는다
        #expect(rollover.unfinishedTasksFromPreviousDays().isEmpty)
    }

    @Test("오늘 일정인 origin task는 복귀하지 않는다 (과거 일정만 대상)")
    func todayScheduledOriginStays() {
        let store = makeTempStore()
        let boundary = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
        let rollover = RolloverService(store: store, dayBoundary: boundary)

        let task = TodoTask(
            title: "오늘 하는 중",
            scheduledDate: boundary.scheduledToday(),
            bucket: .active,
            somedayOrigin: true
        )
        store.addTask(task)

        rollover.returnOverdueSomedayTasks()
        #expect(task.bucket == .active)
        #expect(task.scheduledDate != nil)
        #expect(store.somedayTasks().isEmpty)
        #expect(store.todayTasks(boundary: boundary).map(\.id) == [task.id])
    }

    @Test("완료된 origin task는 복귀하지 않고 히스토리로 남는다")
    func completedOriginNotReturned() {
        let store = makeTempStore()
        let boundary = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
        let rollover = RolloverService(store: store, dayBoundary: boundary)

        let task = TodoTask(
            title: "어제 꺼내 끝냄",
            scheduledDate: date(2026, 7, 21, 9, 0),
            bucket: .active,
            somedayOrigin: true
        )
        task.markCompleted(at: date(2026, 7, 21, 20, 0))
        store.addTask(task)

        rollover.returnOverdueSomedayTasks()
        #expect(task.isCompleted)
        #expect(task.bucket == .active)
        #expect(store.somedayTasks().isEmpty)
    }

    @Test("origin이 아닌 과거 미완료는 복귀 대상이 아니다 (일반 이월 경로 유지)")
    func nonOriginOverdueUntouched() {
        let store = makeTempStore()
        let boundary = DayBoundaryService(settings: makeTestSettings(), now: { date(2026, 7, 22, 10, 0) })
        let rollover = RolloverService(store: store, dayBoundary: boundary)

        let task = TodoTask(title: "그냥 이월 대상", scheduledDate: date(2026, 7, 21, 9, 0))
        store.addTask(task)

        rollover.returnOverdueSomedayTasks()
        #expect(task.scheduledDate != nil)
        #expect(task.bucket == .active)
        // 일반 이월 후보엔 그대로 남는다
        #expect(rollover.unfinishedTasksFromPreviousDays().map(\.id) == [task.id])
    }
}

@MainActor
@Suite("backlog와 someday 구분")
struct BacklogSomedayDistinctionTests {
    @Test("someday 항목은 backlogTasks에 새지 않고, backlog 항목은 somedayTasks에 없다")
    func bucketsDoNotLeak() {
        let store = makeTempStore()
        let backlog = TodoTask(title: "백로그", bucket: .backlog)
        let someday = TodoTask(title: "언젠가", bucket: .someday)
        store.addTask(backlog)
        store.addTask(someday)

        #expect(store.backlogTasks().map(\.id) == [backlog.id])
        #expect(store.somedayTasks().map(\.id) == [someday.id])
    }

    @Test("완료된 someday는 두 목록 어디에도 없다 (미완료 조건)")
    func completedSomedayExcluded() {
        let store = makeTempStore()
        let someday = TodoTask(title: "끝낸 언젠가", bucket: .someday)
        someday.markCompleted(at: date(2026, 7, 22, 11, 0))
        store.addTask(someday)

        #expect(store.somedayTasks().isEmpty)
        #expect(store.backlogTasks().isEmpty)
    }
}
