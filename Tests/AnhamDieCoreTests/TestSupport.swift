import Foundation
@testable import AnhamDieApp

/// Testing.Tag와 모델 Tag의 이름 충돌 회피용 별칭 (모듈명 AnhamDieApp도 @main 타입에 가려 한정 불가).
typealias TaskTag = Tag

func makeTestSettings(boundaryHour: Int = 9, boundaryMinute: Int = 0) -> AppSettings {
    let suite = "AnhamDieTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let settings = AppSettings(defaults: defaults)
    settings.dayBoundaryHour = boundaryHour
    settings.dayBoundaryMinute = boundaryMinute
    return settings
}

func makeTempStoreDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("AnhamDieTests-\(UUID().uuidString)", isDirectory: true)
}

@MainActor
func makeTempStore() -> JSONTaskStore {
    JSONTaskStore(directory: makeTempStoreDirectory())
}

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    Calendar.current.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    )!
}

func midnight(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.startOfDay(for: date(year, month, day, 12))
}
