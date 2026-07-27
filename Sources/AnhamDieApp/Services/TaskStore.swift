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

// MARK: - 표시 순서 단일 소스 (PLAN §11.3)

extension TaskStore {
    /// 표시 순서 비교자 — 모든 목록(메인·오버레이·브리핑·위젯)은 이 순서를 따른다.
    /// sortOrder가 단일 소스, createdAt은 동률(구버전 데이터)의 안정적 타이브레이커.
    nonisolated static func displayOrder(_ a: TodoTask, _ b: TodoTask) -> Bool {
        (a.sortOrder, a.createdAt) < (b.sortOrder, b.createdAt)
    }

    /// 전 태스크의 전역 표시 순서 목록
    func tasksInDisplayOrder() -> [TodoTask] {
        tasks.sorted(by: Self.displayOrder)
    }

    /// 새 태스크 추가의 단일 경로 — 초기 배치 규칙(§11.3: 우선순위 높음 → createdAt 오름차순)에 따라
    /// sortOrder를 부여하고 저장한다. 전역 순서에서 '우선순위 ≥ 새 태스크'인 마지막 항목 뒤에 삽입되므로
    /// 같은 우선순위끼리는 등록순, 드래그로 만든 수동 순서는 흐트러지지 않는다.
    func addTaskApplyingInitialOrder(_ task: TodoTask) {
        var ordered = tasksInDisplayOrder()
        let insertionIndex = (ordered.lastIndex { $0.priority >= task.priority }).map { $0 + 1 } ?? 0
        ordered.insert(task, at: insertionIndex)
        renumber(ordered)
        addTask(task)
    }

    /// 수동 정렬(드래그): taskID 태스크를 targetID 태스크 '앞'으로 이동. 영속된다.
    func reorderTask(id taskID: UUID, before targetID: UUID) {
        moveTask(id: taskID, targetID: targetID, offset: 0)
    }

    /// 수동 정렬(드래그): taskID 태스크를 targetID 태스크 '뒤'로 이동. 영속된다.
    func reorderTask(id taskID: UUID, after targetID: UUID) {
        moveTask(id: taskID, targetID: targetID, offset: 1)
    }

    private func moveTask(id taskID: UUID, targetID: UUID, offset: Int) {
        guard taskID != targetID else { return }
        var ordered = tasksInDisplayOrder()
        guard let from = ordered.firstIndex(where: { $0.id == taskID }) else { return }
        let moving = ordered.remove(at: from)
        guard let targetIndex = ordered.firstIndex(where: { $0.id == targetID }) else { return }
        ordered.insert(moving, at: targetIndex + offset)
        renumber(ordered)
        notifyChanged()
    }

    /// 전역 순서를 0..n-1 정수로 재부여 — sortOrder 유일성 유지
    private func renumber(_ ordered: [TodoTask]) {
        for (index, task) in ordered.enumerated() where task.sortOrder != index {
            task.sortOrder = index
        }
    }
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
        .sorted(by: Self.displayOrder)
    }

    func todayTasks(boundary: DayBoundaryService) -> [TodoTask] {
        tasks(on: boundary.logicalToday(), boundary: boundary)
    }

    /// 백로그: 날짜 없는 미완료
    func backlogTasks() -> [TodoTask] {
        tasks.filter { $0.isActive && $0.scheduledDate == nil }
            .sorted(by: Self.displayOrder)
    }

    /// 예정: due가 있는 미완료
    func upcomingTasks() -> [TodoTask] {
        tasks.filter { $0.isActive && $0.dueDate != nil }
            .sorted { ($0.dueDate ?? .distantFuture, $0.sortOrder) < ($1.dueDate ?? .distantFuture, $1.sortOrder) }
    }

    /// "해야할 일" 뷰의 날짜 그룹 (PLAN §10.1).
    /// 반환 순서: day == nil인 "지난 할 일" 그룹(미완료 overdue·과거 scheduled 통합, 비어 있으면 생략)
    /// → 오늘·내일(비어 있어도 항상 포함) → 태스크가 있는 이후 날짜 오름차순.
    /// day != nil 그룹의 소속 판정은 v1 tasks(on:) 규약(scheduled ∪ due, 완료 당일 포함) 그대로.
    /// "지난 할 일"은 미완료이면서 모든 날짜 키(scheduled/due)가 오늘 이전인 태스크 —
    /// 예: 어제 scheduled + 오늘 due는 지난 그룹이 아니라 오늘 그룹에만 나타난다(중복 없음).
    /// 백로그(scheduledDate·dueDate 모두 nil)는 제외. tagFilter 지정 시 해당 태그 포함 태스크만.
    func scheduleSections(
        boundary: DayBoundaryService,
        tagFilter: Tag? = nil
    ) -> [(day: Date?, tasks: [TodoTask])] {
        let today = boundary.logicalToday()
        let tomorrow = boundary.calendar.date(byAdding: .day, value: 1, to: today)!

        func matchesTag(_ task: TodoTask) -> Bool {
            guard let tag = tagFilter else { return true }
            return task.tagIDs.contains(tag.id)
        }
        func latestDay(_ task: TodoTask) -> Date? {
            [task.scheduledDate, task.dueDate]
                .compactMap { $0.map { boundary.logicalDay(ofStored: $0) } }
                .max()
        }

        let past = tasks
            .filter { task in
                guard task.isActive, matchesTag(task) else { return false }
                guard let latest = latestDay(task) else { return false }
                return latest < today
            }
            .sorted { a, b in
                (latestDay(a) ?? .distantPast, a.sortOrder, a.createdAt)
                    < (latestDay(b) ?? .distantPast, b.sortOrder, b.createdAt)
            }

        var candidateDays: Set<Date> = [today, tomorrow]
        for task in tasks where task.status != .cancelled && matchesTag(task) {
            if let s = task.scheduledDate {
                let day = boundary.logicalDay(ofStored: s)
                if day > today { candidateDays.insert(day) }
            }
            if let d = task.dueDate, task.isActive {
                let day = boundary.logicalDay(ofStored: d)
                if day > today { candidateDays.insert(day) }
            }
        }

        var sections: [(day: Date?, tasks: [TodoTask])] = []
        if !past.isEmpty {
            sections.append((day: nil, tasks: past))
        }
        for day in candidateDays.sorted() {
            let dayTasks = tasks(on: day, boundary: boundary).filter(matchesTag)
            if day == today || day == tomorrow || !dayTasks.isEmpty {
                sections.append((day: day, tasks: dayTasks))
            }
        }
        return sections
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
    /// 예약된 디바운스 저장 작업 — saveNow()/재예약 시 취소해 유효 간격을 0.5s로 유지한다.
    @ObservationIgnored private var saveWorkItem: DispatchWorkItem?
    /// 마지막으로 디스크에서 읽거나(load/merge) 디스크에 쓴(saveNow) 파일의 수정 시각.
    /// mergeFromDisk가 no-op 알림(파일 불변)에서 전체 JSON 디코드를 건너뛰는 데 쓴다.
    @ObservationIgnored private var lastKnownModificationDate: Date?
    /// 디스크의 문서가 이 빌드보다 새 버전이면 true — 덮어쓰기(데이터 소실)를 막기 위해 저장 거부.
    @ObservationIgnored private(set) var saveBlocked = false
    /// saveNow() 성공 직후 호출 (앱 프로세스에서 위젯 타임라인 리로드 등에 사용)
    @ObservationIgnored var onDidSave: (() -> Void)?

    /// 문서 포맷 버전. 키 리네임/타입 변경 등 하위 호환이 깨지는 변경 시 반드시 +1 하고
    /// load()에 구버전 마이그레이션을 추가할 것 (decodeIfPresent로 흡수되는 키 추가는 예외).
    /// v2 (PLAN §11.3·§11.5): recurrence/recurrenceSeriesID 추가 + sortOrder를
    /// 초기 배치 규칙(우선순위 높음 → createdAt 오름차순)으로 전역 재부여.
    static let documentVersion = 2

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
        // 연속 변경마다 재예약(취소 후 재설치) — 트레일링 디바운스로 마지막 변경 0.5s 뒤 1회만 저장한다.
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveWorkItem = nil
            self.saveNow()
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        // 예약된 디바운스 저장이 남아 있으면 취소한다 — 즉시 저장 후 중복 발화 방지.
        saveWorkItem?.cancel()
        saveWorkItem = nil
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
            lastKnownModificationDate = fileModificationDate()
            onDidSave?()
        } catch {
            NSLog("AnhamDie: 저장 실패 — \(error)")
        }
    }

    /// 다른 프로세스(위젯)가 store.json을 바꾼 뒤 호출된다. 디스크 내용을 다시 읽어
    /// 태스크 단위로 머지한다 — 위젯은 완료 토글만 하므로 상태 필드만 갱신하면
    /// 앱의 미저장 변경(새 태스크 등)을 잃지 않는다.
    func mergeFromDisk() {
        // no-op 알림(파일 미변경) 방어: 마지막으로 읽거나 쓴 이후 mtime이 그대로면 디코드조차 하지 않는다.
        let currentMtime = fileModificationDate()
        if let currentMtime, currentMtime == lastKnownModificationDate { return }
        guard let document = decodeDocument() else { return }
        lastKnownModificationDate = currentMtime
        for diskTask in document.tasks {
            if let memory = task(withID: diskTask.id) {
                // 값이 실제로 달라질 때만 대입한다 — Swift Observation은 등가 비교를 하지 않으므로
                // 무조건 대입하면 데이터 불변이어도 열려 있는 모든 표면의 body가 재평가된다.
                if memory.status != diskTask.status { memory.status = diskTask.status }
                if memory.completedAt != diskTask.completedAt { memory.completedAt = diskTask.completedAt }
                if memory.cancelledAt != diskTask.cancelledAt { memory.cancelledAt = diskTask.cancelledAt }
            } else {
                tasks.append(diskTask)
            }
        }
    }

    /// store.json의 현재 수정 시각. 파일이 없거나 stat 실패 시 nil.
    private func fileModificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
    }

    private func load() {
        guard let document = decodeDocument(preserveOnFailure: true) else { return }
        tasks = document.tasks
        tags = document.tags
        lastKnownModificationDate = fileModificationDate()
        if document.version < 2 {
            migrateToV2()
            saveNow() // 디스크를 v2로 확정 (재실행 시 재마이그레이션 방지)
        }
    }

    /// v1 → v2: sortOrder를 §11.3 초기 배치 규칙(우선순위 높음 → createdAt 오름차순)으로 전역 재부여.
    /// v1의 sortOrder는 단순 추가순(max+1)이라 수동 정렬 정보가 없다 — 재부여로 손실되는 것 없음.
    private func migrateToV2() {
        let ordered = tasks.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            return a.createdAt < b.createdAt
        }
        for (index, task) in ordered.enumerated() {
            task.sortOrder = index
        }
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
