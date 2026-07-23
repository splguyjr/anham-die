import SwiftUI

/// 백로그 뷰 (PLAN §10.1 — v1 백로그 탭을 사이드바 뷰로 이관): 날짜 없는 미완료 목록 + 인라인 추가.
struct BacklogListView: View {
    @State private var expandedTaskID: UUID?

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }

    var body: some View {
        let items = store.backlogTasks()
        ScrollView {
            LazyVStack(spacing: 0) {
                ListAddRow(placeholder: "백로그에 추가", onSubmit: addTask)
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
        .navigationTitle("백로그")
    }

    private func addTask(_ title: String) {
        let task = TodoTask(title: title)
        // 초기 배치는 스토어 단일 규칙(§11.3: 우선순위 → createdAt)으로 부여된다.
        store.addTaskApplyingInitialOrder(task)
    }

    private func toggleExpand(_ id: UUID) {
        expandedTaskID = (expandedTaskID == id) ? nil : id
    }
}
