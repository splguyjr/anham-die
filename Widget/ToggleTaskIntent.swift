import AppIntents
import WidgetKit

/// 위젯에서 앱을 열지 않고 완료 상태를 토글하는 인터랙티브 인텐트 (PLAN §3.3).
struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "할 일 완료 토글"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        await WidgetStore.toggleCompletion(taskID: taskID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
