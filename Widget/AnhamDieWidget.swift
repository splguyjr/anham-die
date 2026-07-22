import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let isPreview = context.isPreview
        Task { @MainActor in
            let snapshot = isPreview ? TodaySnapshot.sample : WidgetStore.loadToday()
            completion(TodayEntry(date: snapshot.generatedAt, snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        Task { @MainActor in
            let snapshot = WidgetStore.loadToday()
            let entry = TodayEntry(date: snapshot.generatedAt, snapshot: snapshot)

            // 다음 논리적 하루 경계 또는 1시간 뒤 중 이른 시점에 갱신.
            // (앱은 데이터 변경 시 WidgetCenter.reloadAllTimelines()로 즉시 갱신을 별도 요청한다.)
            let boundary = WidgetStore.makeBoundary()
            let nextBoundary = boundary.nextBoundaryDate()
            let refresh = min(nextBoundary, Date().addingTimeInterval(3600))
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }
}

struct AnhamDieWidget: Widget {
    static let kind = "AnhamDieWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TodayProvider()) { entry in
            AnhamDieWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("오늘 할 일")
        .description("오늘 해야 할 일을 보고 위젯에서 바로 체크하세요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
