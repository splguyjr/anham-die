import Foundation
import Observation

/// 저장소 추상화. 현재 구현은 JSONTaskStore (SwiftData @Model이 CLT에서 빌드 불가 — PLAN §8).
/// 모델 객체는 참조 타입이라 프로퍼티를 직접 수정할 수 있다.
/// 프로퍼티를 직접 수정한 뒤에는 반드시 notifyChanged()를 호출해 영속화를 트리거한다.
/// (add/remove 계열 메서드는 내부에서 알아서 저장한다.)
/// @MainActor: 모델은 비스레드세이프 참조 타입이라 모든 접근을 메인 액터로 강제한다.
/// (2차 SwiftData mainContext 전환 시에도 같은 규약 — off-main 접근은 컴파일 에러가 된다.)
@MainActor
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

    /// 특정 논리적 날짜의 할 일: scheduledDate가 그 날 || dueDate가 그 날.
    /// 취소된 항목은 제외. 완료 항목은 완료한 그 날까지 포함(UI에서 취소선 처리)하고
    /// 다음 논리적 하루부터 숨긴다(PLAN §7) — scheduledDate 분기는 날짜가 달라 자동 제외되고,
    /// dueDate 분기는 completedAt의 논리적 날짜가 그 날일 때만 포함해 같은 규칙을 지킨다.
    func tasks(on day: Date, boundary: DayBoundaryService) -> [TodoTask] {
        tasks.filter { task in
            guard task.status != .cancelled else { return false }
            if let s = task.scheduledDate, boundary.logicalDay(ofStored: s) == day { return true }
            if let d = task.dueDate, boundary.logicalDay(ofStored: d) == day {
                if task.isActive { return true }
                if let c = task.completedAt, boundary.logicalDate(of: c) == day { return true }
            }
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

@MainActor
@Observable
final class JSONTaskStore: TaskStore {
    private(set) var tasks: [TodoTask] = []
    private(set) var tags: [Tag] = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveScheduled = false
    /// 디스크의 문서가 이 빌드보다 새 버전이면 true — 덮어쓰기(데이터 소실)를 막기 위해 저장 거부.
    @ObservationIgnored private(set) var saveBlocked = false
    /// saveNow() 성공 직후 호출 (앱 프로세스에서 위젯 타임라인 리로드 등에 사용)
    @ObservationIgnored var onDidSave: (() -> Void)?

    /// 문서 포맷 버전. 키 리네임/타입 변경 등 하위 호환이 깨지는 변경 시 반드시 +1 하고
    /// load()에 구버전 마이그레이션을 추가할 것 (decodeIfPresent로 흡수되는 키 추가는 예외).
    private static let documentVersion = 1

    private struct Document: Codable {
        var version: Int
        var tasks: [TodoTask]
        var tags: [Tag]
    }

    private struct VersionProbe: Codable {
        var version: Int
    }

    /// ~/Library/Application Support/AnhamDie/store.json
    nonisolated static func defaultDirectory() -> URL {
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
        // 디스크가 이 빌드보다 새 포맷이면 덮어쓰지 않는다 (구버전 실행으로 인한 데이터 소실 방지).
        guard !saveBlocked else {
            NSLog("AnhamDie: 저장 거부 — 디스크 문서 버전이 현재 빌드(v\(Self.documentVersion))보다 높음")
            return
        }
        let document = Document(version: Self.documentVersion, tasks: tasks, tags: tags)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try data.write(to: fileURL, options: .atomic)
            onDidSave?()
        } catch {
            NSLog("AnhamDie: 저장 실패 — \(error)")
        }
    }

    /// 다른 프로세스(위젯)가 store.json을 바꾼 뒤 호출된다. 디스크 내용을 다시 읽어
    /// 태스크 단위로 머지한다 — 위젯은 완료 토글만 하므로 상태 필드만 갱신하면
    /// 앱의 미저장 변경(새 태스크 등)을 잃지 않는다.
    func mergeFromDisk() {
        guard let document = decodeDocument() else { return }
        for diskTask in document.tasks {
            if let memory = task(withID: diskTask.id) {
                memory.status = diskTask.status
                memory.completedAt = diskTask.completedAt
                memory.cancelledAt = diskTask.cancelledAt
            } else {
                tasks.append(diskTask)
            }
        }
    }

    private func load() {
        guard let document = decodeDocument(preserveOnFailure: true) else { return }
        tasks = document.tasks
        tags = document.tags
    }

    /// 디코드 실패 시(preserveOnFailure) 원본을 store.json.corrupt-<timestamp>로 백업해
    /// 이후 saveNow()의 원자적 덮어쓰기로부터 기존 데이터를 보존한다.
    private func decodeDocument(preserveOnFailure: Bool = false) -> Document? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let probe = try? decoder.decode(VersionProbe.self, from: data),
           probe.version > Self.documentVersion {
            NSLog("AnhamDie: 디스크 문서 v\(probe.version) > 지원 v\(Self.documentVersion) — 읽기/쓰기 중단")
            saveBlocked = true
            return nil
        }
        do {
            return try decoder.decode(Document.self, from: data)
        } catch {
            NSLog("AnhamDie: 로드 실패 — \(error)")
            if preserveOnFailure {
                backupCorruptFile()
            }
            return nil
        }
    }

    private func backupCorruptFile() {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("store.json.corrupt-\(stamp)")
        do {
            try FileManager.default.copyItem(at: fileURL, to: backup)
            NSLog("AnhamDie: 손상된 저장소를 백업함 — \(backup.path)")
        } catch {
            // 백업 실패 시 기존 파일을 덮어쓰지 않도록 저장을 잠근다.
            NSLog("AnhamDie: 손상 저장소 백업 실패 — 저장 잠금. \(error)")
            saveBlocked = true
        }
    }
}
