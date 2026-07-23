import Foundation

/// 위젯 프로세스에서 App Group 공유 컨테이너의 store.json을 읽고/쓰는 진입점.
/// 앱과 동일한 JSONTaskStore·DayBoundaryService(논리적 하루 단일 소스, PLAN §5.3)를 그대로 사용한다.
/// JSONTaskStore가 @MainActor라 위젯 진입점도 메인 액터를 경유한다 (Provider는 Task로 홉).
@MainActor
enum WidgetStore {
    /// 공유 UserDefaults에서 기준 시각을 읽어 논리적 하루 서비스를 만든다.
    /// (앱이 공유 suite에 기준 시각을 기록하지 않았다면 기본값 09:00을 쓴다.)
    static func makeBoundary() -> DayBoundaryService {
        let defaults = AppGroup.sharedDefaults() ?? .standard
        let settings = AppSettings(defaults: defaults)
        return DayBoundaryService(settings: settings)
    }

    /// App Group 컨테이너 접근이 불가하면 nil (엔타이틀먼트 없는 환경 등).
    static func makeStore() -> JSONTaskStore? {
        guard let dir = AppGroup.storeDirectory() else { return nil }
        return JSONTaskStore(directory: dir)
    }

    /// 오늘(논리적) 할 일 스냅샷. 접근 불가 시 빈 스냅샷.
    static func loadToday() -> TodaySnapshot {
        guard let store = makeStore() else { return .empty }
        let boundary = makeBoundary()
        let today = store.todayTasks(boundary: boundary)
        let items = today.map { WidgetTask(task: $0, boundary: boundary) }
        let completed = items.filter(\.isCompleted).count
        return TodaySnapshot(generatedAt: boundary.now(), items: items, completedCount: completed)
    }

    /// 위젯 체크박스(AppIntent)에서 호출: 완료/미완료 토글 후 즉시 저장(디바운스 금지 —
    /// perform() 반환 직후 프로세스가 서스펜드되므로 notifyChanged()를 쓰면 안 된다).
    /// 완료 시에는 앱과 동일한 RecurrenceService 단일 경로로 다음 발생을 생성한다(PLAN §11.5) —
    /// 중복 방지 키(시리즈ID+발생 날짜)가 재생성·앱 측 중복을 막고, 새 발생 task는
    /// 앱의 mergeFromDisk가 디스크에서 읽어 흡수한다. 이후 saveNow()가 전체(다음 발생 포함)를
    /// 동기 플러시하고, Darwin notification으로 상주 앱에 알려 lost update를 막는다.
    static func toggleCompletion(taskID: String) {
        guard let uuid = UUID(uuidString: taskID),
              let store = makeStore(),
              let task = store.task(withID: uuid) else { return }
        let boundary = makeBoundary()
        if task.isCompleted {
            task.reactivate()
        } else {
            task.markCompleted(at: boundary.now())
            RecurrenceService(store: store, dayBoundary: boundary)
                .scheduleNextOccurrence(after: task)
        }
        store.saveNow()
        StoreChangeNotifier.post(StoreChangeNotifier.widgetDidChangeStore)
    }
}
