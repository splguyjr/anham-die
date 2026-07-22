import Foundation
import Observation

/// 저장소 추상화. 현재 구현은 JSONTaskStore (SwiftData @Model이 CLT에서 빌드 불가 — PLAN §8).
/// 모델 객체는 참조 타입이라 프로퍼티를 직접 수정할 수 있다.
/// 프로퍼티를 직접 수정한 뒤에는 반드시 notifyChanged()를 호출해 영속화를 트리거한다.
/// (add/remove 계열 메서드는 내부에서 알아서 저장한다.)
protocol TaskStore: AnyObject, Observable {
    var tasks: [TodoTask] { get }
    var tags: [Tag] { get }

    func addTask(_ task: TodoTask)
    func removeTask(_ task: TodoTask)
    func addTag(_ tag: Tag)
    /// 태그 삭제 시 모든 태스크의 tagIDs에서도 제거된다
    func removeTag(_ tag: Tag)

    func task(withID id: UUID) -> TodoTask?
    func tag(withID id: UUID) -> Tag?

    /// 모델 객체를 직접 수정(예: task.markCompleted())한 뒤 호출. 저장을 예약한다.
    func notifyChanged()
    /// 즉시 디스크에 플러시 (앱 종료 시 등)
    func saveNow()
}

// MARK: - 공용 쿼리 헬퍼

extension TaskStore {
    func tags(of task: TodoTask) -> [Tag] {
        task.tagIDs.compactMap { tag(withID: $0) }
    }

    /// 특정 논리적 날짜의 할 일: scheduledDate가 그 날 || (dueDate가 그 날 && 미완료).
    /// 취소된 항목은 제외. 완료 항목은 포함(UI에서 취소선 처리, 다음 날부터는 날짜가 달라 자동 제외).
    func tasks(on day: Date, boundary: DayBoundaryService) -> [TodoTask] {
        tasks.filter { task in
            guard task.status != .cancelled else { return false }
            if let s = task.scheduledDate, boundary.logicalDate(of: s) == day { return true }
            if task.isActive, let d = task.dueDate, boundary.logicalDate(of: d) == day { return true }
            return false
        }
        .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    func todayTasks(boundary: DayBoundaryService) -> [TodoTask] {
        tasks(on: boundary.logicalToday(), boundary: boundary)
    }

    /// 백로그: 날짜 없는 미완료
    func backlogTasks() -> [TodoTask] {
        tasks.filter { $0.isActive && $0.scheduledDate == nil }
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    /// 예정: due가 있는 미완료
    func upcomingTasks() -> [TodoTask] {
        tasks.filter { $0.isActive && $0.dueDate != nil }
            .sorted { ($0.dueDate ?? .distantFuture, $0.sortOrder) < ($1.dueDate ?? .distantFuture, $1.sortOrder) }
    }

    /// 완료 히스토리 (completedAt 내림차순)
    func completedTasks() -> [TodoTask] {
        tasks.filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// 취소('버리기') 히스토리 (cancelledAt 내림차순)
    func cancelledTasks() -> [TodoTask] {
        tasks.filter { $0.status == .cancelled }
            .sorted { ($0.cancelledAt ?? .distantPast) > ($1.cancelledAt ?? .distantPast) }
    }
}

// MARK: - JSON 파일 스토어

@Observable
final class JSONTaskStore: TaskStore {
    private(set) var tasks: [TodoTask] = []
    private(set) var tags: [Tag] = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveScheduled = false

    private struct Document: Codable {
        var version: Int
        var tasks: [TodoTask]
        var tags: [Tag]
    }

    /// ~/Library/Application Support/AnhamDie/store.json
    static func defaultDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AnhamDie", isDirectory: true)
    }

    static func makeDefault() -> JSONTaskStore {
        JSONTaskStore(directory: defaultDirectory())
    }

    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("store.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    func addTask(_ task: TodoTask) {
        tasks.append(task)
        notifyChanged()
    }

    func removeTask(_ task: TodoTask) {
        tasks.removeAll { $0.id == task.id }
        notifyChanged()
    }

    func addTag(_ tag: Tag) {
        tags.append(tag)
        notifyChanged()
    }

    func removeTag(_ tag: Tag) {
        tags.removeAll { $0.id == tag.id }
        for task in tasks where task.tagIDs.contains(tag.id) {
            task.tagIDs.removeAll { $0 == tag.id }
        }
        notifyChanged()
    }

    func task(withID id: UUID) -> TodoTask? {
        tasks.first { $0.id == id }
    }

    func tag(withID id: UUID) -> Tag? {
        tags.first { $0.id == id }
    }

    func notifyChanged() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.saveScheduled else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        saveScheduled = false
        let document = Document(version: 1, tasks: tasks, tags: tags)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("AnhamDie: 저장 실패 — \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(Document.self, from: data)
            tasks = document.tasks
            tags = document.tags
        } catch {
            NSLog("AnhamDie: 로드 실패 — \(error)")
        }
    }
}
