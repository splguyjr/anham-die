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
    /// 주간 목표 (v11 §20.1) — task와 같은 store.json에 통합 저장(문서 v3)
    var weeklyGoals: [WeeklyGoal] { get }

    func addTask(_ task: TodoTask)
    func removeTask(_ task: TodoTask)
    func addTag(_ tag: Tag)
    /// 태그 삭제 시 모든 태스크의 tagIDs에서도 제거된다
    func removeTag(_ tag: Tag)
    func addWeeklyGoal(_ goal: WeeklyGoal)
    /// 목표 삭제 시 연결 task의 weeklyGoalID도 끊는다 (배지 잔존 방지)
    func removeWeeklyGoal(_ goal: WeeklyGoal)

    func task(withID id: UUID) -> TodoTask?
    func tag(withID id: UUID) -> Tag?
    func weeklyGoal(withID id: UUID) -> WeeklyGoal?

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

// MARK: - 주간 목표 (v11 §20.1·§20.2)

extension TaskStore {
    /// 특정 논리적 주(주 시작 날짜 키)의 목표 — createdAt 오름차순.
    /// 사이드바 주간 목표 뷰·요약 스트립·캘린더 주간 헤더·브리핑 미니 요약(§20.4)의 단일 쿼리.
    func weeklyGoals(forWeek weekStart: Date, boundary: DayBoundaryService) -> [WeeklyGoal] {
        weeklyGoals
            .filter { boundary.logicalDay(ofStored: $0.weekKey) == weekStart }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    /// 지난 주 기록(주별 그룹) — weekKey 내림차순 (최근 주 먼저), 주 안은 createdAt 오름차순.
    func weeklyGoalsGroupedByWeek(boundary: DayBoundaryService) -> [(week: Date, goals: [WeeklyGoal])] {
        let byWeek = Dictionary(grouping: weeklyGoals) { boundary.logicalDay(ofStored: $0.weekKey) }
        return byWeek.keys.sorted(by: >).map { week in
            (week: week, goals: weeklyGoals(forWeek: week, boundary: boundary))
        }
    }

    /// 목표 진행 +1 (§20.2) — 초과 달성 허용(target 클램프 없음). 직접 +1 버튼·완료 확정 훅 공용.
    func incrementGoalCount(id: UUID) {
        guard let goal = weeklyGoal(withID: id) else { return }
        goal.currentCount += 1
        notifyChanged()
    }

    /// 목표 진행 -1 (§20.2) — 0 미만 방지. 직접 -1 버튼·완료 취소(reactivate) 훅 공용.
    func decrementGoalCount(id: UUID) {
        guard let goal = weeklyGoal(withID: id), goal.currentCount > 0 else { return }
        goal.currentCount -= 1
        notifyChanged()
    }

    /// [오늘 하기] (§20.2): 목표에 연결된 task를 오늘에 생성 (weeklyGoalID 연결 → 행 ↗주간 배지).
    /// 오늘 이미 활성 연결 task가 있으면 중복 생성 없이 그것을 돌려준다 (버튼 연타 멱등).
    /// 생성 task는 일반 task와 동일하게 이월·백로그·삭제 가능 — 삭제해도 이미 오른 카운트는 유지.
    @discardableResult
    func createLinkedTask(goal: WeeklyGoal, boundary: DayBoundaryService) -> TodoTask {
        if let existing = todayLinkedTask(goal: goal, boundary: boundary) {
            return existing
        }
        let task = TodoTask(
            title: goal.title,
            createdAt: boundary.now(),
            scheduledDate: boundary.scheduledToday(),
            weeklyGoalID: goal.id
        )
        addTaskApplyingInitialOrder(task)
        return task
    }

    /// 오늘에 연결된 **미완료** task (있으면 반환) — [오늘 하기] 토글·버튼 상태의 단일 기준.
    /// 완료(또는 취소)된 연결 task는 대상 아님(isActive 필터) → 카운트에 반영된 달성은 건드리지 않는다.
    func todayLinkedTask(goal: WeeklyGoal, boundary: DayBoundaryService) -> TodoTask? {
        let today = boundary.logicalToday()
        return tasks.first { task in
            task.isActive && task.weeklyGoalID == goal.id
                && task.scheduledDate.map { boundary.logicalDay(ofStored: $0) } == today
        }
    }

    /// 오늘 연결 미완료 task 존재 여부 (버튼 "오늘 있음/없음" 선택 상태 표시용).
    func hasTodayLink(goal: WeeklyGoal, boundary: DayBoundaryService) -> Bool {
        todayLinkedTask(goal: goal, boundary: boundary) != nil
    }

    /// [오늘 하기] 토글 (§21.1 공용 액션): 오늘 연결 미완료 task가 없으면 생성, 있으면 제거.
    /// 미완료 task 제거는 아직 오르지 않은 진행이므로 목표 카운트는 불변. 완료된 연결 task는
    /// 대상이 아니라 그대로 두므로(달성 카운트 유지) 완료 뒤 다시 누르면 오늘에 새로 배치된다.
    /// 반환값: 토글 후 오늘에 연결이 있으면 true(배치됨), 없으면 false(해제됨).
    @discardableResult
    func toggleTodayLink(goal: WeeklyGoal, boundary: DayBoundaryService) -> Bool {
        if let existing = todayLinkedTask(goal: goal, boundary: boundary) {
            removeTask(existing)
            return false
        }
        createLinkedTask(goal: goal, boundary: boundary)
        return true
    }
}

// MARK: - JSON 파일 스토어

@MainActor
@Observable
final class JSONTaskStore: TaskStore {
    private(set) var tasks: [TodoTask] = []
    private(set) var tags: [Tag] = []
    private(set) var weeklyGoals: [WeeklyGoal] = []

    /// 영속화 공용 엔진 (v10 §19.4 공용화) — 디바운스·버전 잠금·.corrupt 백업·mtime 추적 위임.
    @ObservationIgnored private let persistence: JSONDocumentPersistence<Document>

    /// 디스크의 문서가 이 빌드보다 새 버전이면 true — 덮어쓰기(데이터 소실)를 막기 위해 저장 거부.
    var saveBlocked: Bool { persistence.saveBlocked }
    /// saveNow() 성공 직후 호출 (앱 프로세스에서 위젯 타임라인 리로드 등에 사용)
    var onDidSave: (() -> Void)? {
        get { persistence.onDidSave }
        set { persistence.onDidSave = newValue }
    }

    /// 문서 포맷 버전. 키 리네임/타입 변경 등 하위 호환이 깨지는 변경 시 반드시 +1 하고
    /// load()에 구버전 마이그레이션을 추가할 것 (decodeIfPresent로 흡수되는 키 추가는 예외).
    /// v2 (PLAN §11.3·§11.5): recurrence/recurrenceSeriesID 추가 + sortOrder를
    /// 초기 배치 규칙(우선순위 높음 → createdAt 오름차순)으로 전역 재부여.
    /// v3 (PLAN §20.5): weeklyGoals 배열 + task.weeklyGoalID 추가 — 데이터 변형 없음(키 추가만).
    /// 버전 업 이유: 구버전(≤1.3.0) 실행이 goals 키를 몰라 저장 시 통째로 유실시키는 것을
    /// 버전 잠금(saveBlocked)으로 차단하기 위함.
    static let documentVersion = 3

    private struct Document: Codable {
        var version: Int
        var tasks: [TodoTask]
        var tags: [Tag]
        /// v3 추가 — v2 이하 문서엔 키가 없어 decodeIfPresent로 흡수한다
        var weeklyGoals: [WeeklyGoal]?
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
        self.persistence = JSONDocumentPersistence(
            directory: directory, fileName: "store.json", supportedVersion: Self.documentVersion
        )
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

    func addWeeklyGoal(_ goal: WeeklyGoal) {
        weeklyGoals.append(goal)
        notifyChanged()
    }

    func removeWeeklyGoal(_ goal: WeeklyGoal) {
        weeklyGoals.removeAll { $0.id == goal.id }
        // 연결 task의 배지 참조를 끊는다 — 이미 오른 카운트는 목표 삭제와 함께 사라지는 게 자연스럽고,
        // task 자체는 일반 task로 남는다 (§20.2).
        for task in tasks where task.weeklyGoalID == goal.id {
            task.weeklyGoalID = nil
        }
        notifyChanged()
    }

    func task(withID id: UUID) -> TodoTask? {
        tasks.first { $0.id == id }
    }

    func tag(withID id: UUID) -> Tag? {
        tags.first { $0.id == id }
    }

    func weeklyGoal(withID id: UUID) -> WeeklyGoal? {
        weeklyGoals.first { $0.id == id }
    }

    func notifyChanged() {
        // 트레일링 디바운스(0.5s) — 엔진이 재예약을 관리한다. 문서 스냅숏은 발화 시점에 만든다.
        persistence.scheduleSave { [weak self] in self?.currentDocument() }
    }

    func saveNow() {
        persistence.saveNow(currentDocument())
    }

    private func currentDocument() -> Document {
        Document(version: Self.documentVersion, tasks: tasks, tags: tags, weeklyGoals: weeklyGoals)
    }

    /// 다른 프로세스(위젯)가 store.json을 바꾼 뒤 호출된다. 디스크 내용을 다시 읽어
    /// 태스크·주간 목표를 필드 단위로 머지한다 — 위젯은 완료 토글(+연동 목표 증감, §20.2)만
    /// 하므로 변하는 필드만 채택하면 앱의 미저장 변경(새 태스크 등)을 잃지 않는다.
    /// no-op 알림(파일 미변경) 방어는 엔진의 mtime 추적이 담당한다.
    func mergeFromDisk() {
        guard let document = persistence.decodeIfChangedOnDisk() else { return }
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
        // 목표 카운트를 머지하지 않으면 위젯 완료가 올린 +1이 앱 메모리에 반영되지 않고(스테일 0),
        // 이후 앱이 아무 변경으로든 저장할 때 디스크의 +1까지 되돌린다(lost update). 위젯은
        // currentCount 증감만 하므로 이 필드만 디스크 값으로 채택하고, 메모리에 없는 goal은 흡수한다.
        for diskGoal in document.weeklyGoals ?? [] {
            if let memory = weeklyGoal(withID: diskGoal.id) {
                // 값이 다를 때만 대입 — task 머지와 동일한 관찰 규약(불필요한 body 재평가 방지).
                if memory.currentCount != diskGoal.currentCount { memory.currentCount = diskGoal.currentCount }
            } else {
                weeklyGoals.append(diskGoal)
            }
        }
    }

    private func load() {
        guard let document = persistence.load() else { return }
        tasks = document.tasks
        tags = document.tags
        weeklyGoals = document.weeklyGoals ?? [] // v2 이하 문서엔 없음 — 빈 목록으로 시작
        if document.version < 2 {
            migrateToV2()
        }
        if document.version < Self.documentVersion {
            // 디스크를 현재 버전으로 확정 — 재실행 시 재마이그레이션 방지 + 구버전 실행의
            // 덮어쓰기(goals 유실)를 버전 잠금으로 차단. v3는 키 추가만이라 데이터 변형 없음.
            saveNow()
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

}
