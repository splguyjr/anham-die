import Foundation

/// 위젯 타임라인 엔트리에 담기는 태스크의 값 스냅샷.
/// TodoTask(참조 타입)를 직접 넣지 않고 표시에 필요한 값만 복사해 Sendable로 유지한다.
struct WidgetTask: Identifiable, Hashable, Sendable {
    let id: String          // TodoTask.id.uuidString — ToggleTaskIntent 파라미터로 사용
    let title: String
    let isCompleted: Bool
    let isOverdue: Bool
    let dDayText: String?
    let priorityColorHex: String?

    init(
        id: String,
        title: String,
        isCompleted: Bool,
        isOverdue: Bool,
        dDayText: String?,
        priorityColorHex: String?
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.isOverdue = isOverdue
        self.dDayText = dDayText
        self.priorityColorHex = priorityColorHex
    }

    init(task: TodoTask, boundary: DayBoundaryService) {
        self.id = task.id.uuidString
        self.title = task.title
        self.isCompleted = task.isCompleted
        if task.isActive, let due = task.dueDate {
            let d = boundary.dDay(of: due)
            self.isOverdue = d < 0
            self.dDayText = WidgetTask.dDayLabel(d)
        } else {
            self.isOverdue = false
            self.dDayText = nil
        }
        self.priorityColorHex = task.priority == .high ? "#FF3B30" : nil
    }

    static func dDayLabel(_ d: Int) -> String {
        if d == 0 { return "D-DAY" }
        if d > 0 { return "D-\(d)" }
        return "D+\(-d)"
    }

    static let samples: [WidgetTask] = [
        WidgetTask(id: "s1", title: "결제 워크플로우", isCompleted: false, isOverdue: true, dDayText: "D+1", priorityColorHex: "#FF3B30"),
        WidgetTask(id: "s2", title: "Docker 실습", isCompleted: false, isOverdue: false, dDayText: nil, priorityColorHex: nil),
        WidgetTask(id: "s3", title: "도시락 통 알아보기", isCompleted: true, isOverdue: false, dDayText: nil, priorityColorHex: nil),
        WidgetTask(id: "s4", title: "회고 문서 작성", isCompleted: false, isOverdue: false, dDayText: "D-2", priorityColorHex: nil)
    ]
}

/// 오늘 할 일 전체 스냅샷 + 진행률.
struct TodaySnapshot: Sendable {
    let generatedAt: Date
    let items: [WidgetTask]
    let completedCount: Int

    var totalCount: Int { items.count }

    init(generatedAt: Date, items: [WidgetTask], completedCount: Int) {
        self.generatedAt = generatedAt
        self.items = items
        self.completedCount = completedCount
    }

    static let empty = TodaySnapshot(generatedAt: Date(), items: [], completedCount: 0)

    static var sample: TodaySnapshot {
        TodaySnapshot(
            generatedAt: Date(),
            items: WidgetTask.samples,
            completedCount: WidgetTask.samples.filter(\.isCompleted).count
        )
    }
}
