import Foundation
import Observation

// CLT 툴체인에 SwiftDataMacros 플러그인이 없어 @Model을 쓸 수 없다 (PLAN §8 폴백).
// 모델은 @Observable + 수동 Codable, 영속화는 JSONTaskStore가 담당한다.
// @Observable이 저장 프로퍼티를 _언더스코어 백킹으로 바꾸므로 Codable 합성이 불가능해
// init(from:)/encode(to:)를 직접 구현한다.

enum Priority: Int, Codable, CaseIterable, Comparable, Sendable {
    case low = 0
    case normal = 1
    case high = 2

    static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .high: return "높음"
        case .normal: return "보통"
        case .low: return "낮음"
        }
    }
}

enum TaskStatus: String, Codable, Sendable {
    case active
    case completed
    case cancelled
}

/// 반복 규칙 (PLAN §11.5). weekly의 요일은 Calendar.weekday 값(1=일 … 7=토).
enum RecurrenceRule: Equatable, Hashable, Codable, Sendable {
    case none
    case daily
    case weekdays
    case weekly(Set<Int>)

    /// 논리적 날짜 base(자정 정규화) '이후'의 다음 발생 논리적 날짜.
    /// none 또는 요일이 비어 있는 weekly는 nil (다음 발생 없음).
    func nextOccurrence(after base: Date, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: base)
        switch self {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: start)
        case .weekdays:
            return Self.scanForward(from: start, calendar: calendar) { (2...6).contains($0) }
        case .weekly(let days):
            guard !days.isEmpty else { return nil }
            return Self.scanForward(from: start, calendar: calendar) { days.contains($0) }
        }
    }

    private static func scanForward(
        from start: Date, calendar: Calendar, matches: (Int) -> Bool
    ) -> Date? {
        var day = start
        for _ in 0..<7 {
            day = calendar.date(byAdding: .day, value: 1, to: day)!
            if matches(calendar.component(.weekday, from: day)) { return day }
        }
        return nil
    }

    var displayName: String {
        switch self {
        case .none: return "반복 안 함"
        case .daily: return "매일"
        case .weekdays: return "평일"
        case .weekly(let days):
            let symbols = ["일", "월", "화", "수", "목", "금", "토"]
            let names = days.sorted().compactMap { (1...7).contains($0) ? symbols[$0 - 1] : nil }
            return names.isEmpty ? "매주" : "매주 " + names.joined(separator: "·")
        }
    }

    // MARK: - Codable — {"kind": "...", "weekdays": [Int]?} 판별자 방식

    private enum CodingKeys: String, CodingKey { case kind, weekdays }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "daily": self = .daily
        case "weekdays": self = .weekdays
        case "weekly": self = .weekly(Set(try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? []))
        default: self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none: try c.encode("none", forKey: .kind)
        case .daily: try c.encode("daily", forKey: .kind)
        case .weekdays: try c.encode("weekdays", forKey: .kind)
        case .weekly(let days):
            try c.encode("weekly", forKey: .kind)
            try c.encode(days.sorted(), forKey: .weekdays)
        }
    }
}

@Observable
final class TodoTask: Identifiable, Codable {
    var id: UUID
    var title: String
    var note: String
    var createdAt: Date
    /// 어느 "논리적 하루"에 속하는지. nil = 백로그. 날짜 비교는 DayBoundaryService.logicalDate(of:)로.
    var scheduledDate: Date?
    var dueDate: Date?
    var completedAt: Date?
    var cancelledAt: Date?
    var status: TaskStatus
    var priority: Priority
    var rolloverCount: Int
    var sortOrder: Int
    /// 다대다 태그는 ID 참조. 실제 Tag 객체는 TaskStore.tags(of:)로 조회.
    var tagIDs: [UUID]
    var subtasks: [Subtask]
    /// 반복 규칙 (PLAN §11.5). 구버전 문서에는 없음 — 로드 시 .none.
    var recurrence: RecurrenceRule
    /// 반복 시리즈 식별자 — 다음 발생 중복 생성 방지 키(시리즈ID + 발생 날짜).
    /// 첫 발생 생성 시 원본 task.id로 채워지고 이후 발생에 승계된다.
    var recurrenceSeriesID: UUID?
    /// 연결된 주간 목표 (v11 §20.2, 행의 ↗주간 배지). 완료 확정 시 목표 +1, 완료 취소 시 -1은
    /// CompletionGraceController·store 카운트 API가 담당. 목표/task 삭제 시 카운트는 유지된다.
    var weeklyGoalID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        createdAt: Date = Date(),
        scheduledDate: Date? = nil,
        dueDate: Date? = nil,
        completedAt: Date? = nil,
        cancelledAt: Date? = nil,
        status: TaskStatus = .active,
        priority: Priority = .normal,
        rolloverCount: Int = 0,
        sortOrder: Int = 0,
        tagIDs: [UUID] = [],
        subtasks: [Subtask] = [],
        recurrence: RecurrenceRule = .none,
        recurrenceSeriesID: UUID? = nil,
        weeklyGoalID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.createdAt = createdAt
        self.scheduledDate = scheduledDate
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.cancelledAt = cancelledAt
        self.status = status
        self.priority = priority
        self.rolloverCount = rolloverCount
        self.sortOrder = sortOrder
        self.tagIDs = tagIDs
        self.subtasks = subtasks
        self.recurrence = recurrence
        self.recurrenceSeriesID = recurrenceSeriesID
        self.weeklyGoalID = weeklyGoalID
    }

    var isCompleted: Bool { status == .completed }
    var isActive: Bool { status == .active }
    /// 행의 ↻ 배지 표시 여부 (PLAN §11.5)
    var isRecurring: Bool { recurrence != .none }

    func markCompleted(at date: Date = Date()) {
        status = .completed
        completedAt = date
        cancelledAt = nil
    }

    func markCancelled(at date: Date = Date()) {
        status = .cancelled
        cancelledAt = date
        completedAt = nil
    }

    func reactivate() {
        status = .active
        completedAt = nil
        cancelledAt = nil
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, title, note, createdAt, scheduledDate, dueDate, completedAt, cancelledAt
        case status, priority, rolloverCount, sortOrder, tagIDs, subtasks
        case recurrence, recurrenceSeriesID, weeklyGoalID
    }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            title: try c.decode(String.self, forKey: .title),
            note: try c.decodeIfPresent(String.self, forKey: .note) ?? "",
            createdAt: try c.decode(Date.self, forKey: .createdAt),
            scheduledDate: try c.decodeIfPresent(Date.self, forKey: .scheduledDate),
            dueDate: try c.decodeIfPresent(Date.self, forKey: .dueDate),
            completedAt: try c.decodeIfPresent(Date.self, forKey: .completedAt),
            cancelledAt: try c.decodeIfPresent(Date.self, forKey: .cancelledAt),
            status: try c.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .active,
            priority: try c.decodeIfPresent(Priority.self, forKey: .priority) ?? .normal,
            rolloverCount: try c.decodeIfPresent(Int.self, forKey: .rolloverCount) ?? 0,
            sortOrder: try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0,
            tagIDs: try c.decodeIfPresent([UUID].self, forKey: .tagIDs) ?? [],
            subtasks: try c.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? [],
            recurrence: try c.decodeIfPresent(RecurrenceRule.self, forKey: .recurrence) ?? .none,
            recurrenceSeriesID: try c.decodeIfPresent(UUID.self, forKey: .recurrenceSeriesID),
            weeklyGoalID: try c.decodeIfPresent(UUID.self, forKey: .weeklyGoalID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(note, forKey: .note)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(scheduledDate, forKey: .scheduledDate)
        try c.encodeIfPresent(dueDate, forKey: .dueDate)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(cancelledAt, forKey: .cancelledAt)
        try c.encode(status, forKey: .status)
        try c.encode(priority, forKey: .priority)
        try c.encode(rolloverCount, forKey: .rolloverCount)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(tagIDs, forKey: .tagIDs)
        try c.encode(subtasks, forKey: .subtasks)
        try c.encode(recurrence, forKey: .recurrence)
        try c.encodeIfPresent(recurrenceSeriesID, forKey: .recurrenceSeriesID)
        try c.encodeIfPresent(weeklyGoalID, forKey: .weeklyGoalID)
    }
}

@Observable
final class Subtask: Identifiable, Codable {
    var id: UUID
    var title: String
    var isDone: Bool
    var sortOrder: Int

    init(id: UUID = UUID(), title: String, isDone: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey { case id, title, isDone, sortOrder }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            title: try c.decode(String.self, forKey: .title),
            isDone: try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false,
            sortOrder: try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(isDone, forKey: .isDone)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

@Observable
final class Tag: Identifiable, Codable {
    var id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String = "#8E8E93") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    private enum CodingKeys: String, CodingKey { case id, name, colorHex }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try c.decode(String.self, forKey: .name),
            colorHex: try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#8E8E93"
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(colorHex, forKey: .colorHex)
    }
}
