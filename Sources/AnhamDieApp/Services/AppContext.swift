import Foundation

/// 앱 전역 서비스 컨테이너. 모든 모듈은 AppContext.shared를 통해 공용 서비스에 접근한다.
@MainActor
final class AppContext {
    static let shared = AppContext()

    let settings: AppSettings
    let store: TaskStore
    let dayBoundary: DayBoundaryService
    let rollover: RolloverService
    let triggers: TriggerService

    private init() {
        let settings = AppSettings.shared
        let store = JSONTaskStore.makeDefault()
        let dayBoundary = DayBoundaryService(settings: settings)
        self.settings = settings
        self.store = store
        self.dayBoundary = dayBoundary
        self.rollover = RolloverService(store: store, dayBoundary: dayBoundary)
        self.triggers = TriggerService(settings: settings, dayBoundary: dayBoundary)
    }
}
