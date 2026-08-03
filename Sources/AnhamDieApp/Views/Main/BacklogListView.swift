import SwiftUI

/// 백로그 뷰 (PLAN §10.1 — v1 백로그 탭을 사이드바 뷰로 이관): 날짜 없는 미완료 목록 + 인라인 추가.
struct BacklogListView: View {
    @State private var expandedTaskID: UUID?

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }
    private var settings: AppSettings { AppContext.shared.settings }

    var body: some View {
        let items = store.backlogTasks()
        ScrollView {
            LazyVStack(spacing: 0) {
                // 토큰 문법(#태그 !우선순위 날짜) 지원 (PLAN §11.8). 날짜 토큰 없으면 백로그(날짜 없음)에 남는다.
                MainTokenAddRow(placeholder: "백로그에 추가", onSubmit: addTask)
                ListRowDivider()
                if items.isEmpty {
                    ListEmptyState(message: "백로그가 비어 있습니다", systemImage: "tray")
                }
                ForEach(items) { task in
                    MainTaskRow(
                        task: task,
                        store: store,
                        boundary: boundary,
                        isExpanded: expandedTaskID == task.id,
                        onToggleExpand: { toggleExpand(task.id) }
                    )
                    ListRowDivider()
                }
            }
            .padding(.horizontal, AppTheme.contentPadding)
            .padding(.bottom, 24)
        }
        .background(AppTheme.surface)
        // §17: 메인 리스트 계열에서만 메모 미리보기 opt-in.
        .environment(\.taskRowShowsNotePreview, true)
        .navigationTitle("백로그")
    }

    // 백로그 기본은 날짜 없음. 날짜 토큰이 있으면 그 날짜로 예정되어 백로그를 벗어난다.
    private func addTask(_ parse: QuickAddParse) {
        MainInlineAdd.commit(
            parse,
            defaultScheduled: nil,
            extraTag: nil,
            store: store,
            boundary: boundary,
            settings: settings
        )
    }

    private func toggleExpand(_ id: UUID) {
        expandedTaskID = (expandedTaskID == id) ? nil : id
    }
}
