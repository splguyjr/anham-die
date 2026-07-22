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
        self.triggers = TriggerService(settings: settings, dayBoundary: dayBoundary)

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
        // 되돌리는 lost update를 막는다.
        widgetChangeObserver = DarwinNotificationObserver(
            name: StoreChangeNotifier.widgetDidChangeStore
        ) { [weak store] in
            MainActor.assumeIsolated {
                store?.mergeFromDisk()
            }
        }
    }
}
