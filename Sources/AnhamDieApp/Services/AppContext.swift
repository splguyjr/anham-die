import Foundation
import WidgetKit

/// 앱 전역 서비스 컨테이너. 모든 모듈은 AppContext.shared를 통해 공용 서비스에 접근한다.
@MainActor
final class AppContext {
    static let shared = AppContext()

    let settings: AppSettings
    let store: TaskStore
    let dayBoundary: DayBoundaryService
    let rollover: RolloverService
    let recurrence: RecurrenceService
    let triggers: TriggerService

    private var widgetChangeObserver: DarwinNotificationObserver?
    private var boundaryChangeObserver: NSObjectProtocol?

    private init() {
        let settings = AppSettings.shared
        // App Group 컨테이너 접근이 가능하면(Xcode 서명 빌드) 기존 저장소를 공유 경로로 1회 이전 후
        // 그 경로를 쓴다 — 위젯이 앱과 같은 store.json을 보게 하기 위함. 불가하면 Application Support.
        let storeDirectory = SharedStoreMigration.migrateIfNeeded() ?? JSONTaskStore.defaultDirectory()
        let store = JSONTaskStore(directory: storeDirectory)
        let dayBoundary = DayBoundaryService(settings: settings)
        self.settings = settings
        self.store = store
        self.dayBoundary = dayBoundary
        self.rollover = RolloverService(store: store, dayBoundary: dayBoundary)
        self.recurrence = RecurrenceService(store: store, dayBoundary: dayBoundary)
        self.triggers = TriggerService(settings: settings, dayBoundary: dayBoundary)
        // 뷰 관찰용 '현재 논리적 날짜' 초기화 — 이후 갱신은 TriggerService(경계 타이머/웨이크 등)가 담당.
        settings.currentLogicalDay = dayBoundary.logicalToday()

        // 위젯 타임라인은 시스템 갱신 주기가 느리므로 데이터 저장/기준 시각 변경 시 명시적으로 리로드.
        store.onDidSave = {
            WidgetCenter.shared.reloadAllTimelines()
        }
        boundaryChangeObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.dayBoundaryDidChange, object: nil, queue: .main
        ) { _ in
            WidgetCenter.shared.reloadAllTimelines()
        }
        // 위젯이 완료를 토글하면 디스크에서 다시 읽어 머지 — 앱의 다음 저장이 위젯 변경을
        // 되돌리는 lost update를 막는다. 이어서 반복 task의 다음 회차를 보정한다:
        // 위젯이 만든 다음 발생은 머지로 흡수되고, 누락됐다면 앱이 대신 생성한다 (§11.5 안전망).
        widgetChangeObserver = DarwinNotificationObserver(
            name: StoreChangeNotifier.widgetDidChangeStore
        ) { [weak self, weak store] in
            MainActor.assumeIsolated {
                store?.mergeFromDisk()
                self?.backfillRecurrences()
            }
        }
    }

    /// 위젯이 완료·취소한 반복 task의 다음 회차를 앱 측에서 보정한다 (PLAN §11.5 안전망).
    /// 위젯도 자체 프로세스에서 다음 발생을 생성하지만, 그 경로가 누락·실패하면 여기서 채운다.
    /// 위젯 변경 알림(Darwin) 수신 시에만 호출한다 — 앱 내부 삭제·완료는 이 경로를 타지 않으므로
    /// 사용자가 지운 다음 회차를 되살리지 않는다.
    /// '완료·취소 상태 + recurrence ≠ none + 시리즈에 활성 발생 없음'인 task마다 다음 발생을 만든다.
    /// scheduleNextOccurrence의 (시리즈ID, 발생일) 중복 방지로 위젯이 이미 만든 회차와 겹치지 않으며,
    /// 시리즈에 활성 발생이 남아 있으면(정상 진행 중) 건너뛰어 회차가 쌓이지 않는다.
    private func backfillRecurrences() {
        for task in store.tasks where !task.isActive && task.recurrence != .none {
            let seriesID = task.recurrenceSeriesID ?? task.id
            let hasActiveOccurrence = store.tasks.contains { other in
                other.id != task.id
                    && other.isActive
                    && (other.recurrenceSeriesID ?? other.id) == seriesID
            }
            guard !hasActiveOccurrence else { continue }
            recurrence.scheduleNextOccurrence(after: task)
        }
    }
}
