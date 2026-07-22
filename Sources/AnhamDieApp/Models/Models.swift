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
        subtasks: [Subtask] = []
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
    }

    var isCompleted: Bool { status == .completed }
    var isActive: Bool { status == .active }

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
            subtasks: try c.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
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
