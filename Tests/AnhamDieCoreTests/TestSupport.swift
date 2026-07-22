import Foundation
@testable import AnhamDieApp

func makeTestSettings(boundaryHour: Int = 9, boundaryMinute: Int = 0) -> AppSettings {
    let suite = "AnhamDieTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let settings = AppSettings(defaults: defaults)
    settings.dayBoundaryHour = boundaryHour
    settings.dayBoundaryMinute = boundaryMinute
    return settings
}

func makeTempStore() -> JSONTaskStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("AnhamDieTests-\(UUID().uuidString)", isDirectory: true)
    return JSONTaskStore(directory: dir)
}

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    Calendar.current.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    )!
}

func midnight(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.startOfDay(for: date(year, month, day, 12))
}
