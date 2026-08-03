import SwiftUI

/// 완료 히스토리 뷰 (PLAN §10.1 — v1 완료 탭을 사이드바 뷰로 이관): 논리적 날짜별 그룹 + 취소됨.
struct DoneListView: View {
    @State private var expandedTaskID: UUID?

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E)"
        return f
    }()

    var body: some View {
        // 관찰: 논리적 하루 경계 통과 시 TriggerService가 갱신 → '오늘'/'어제' 라벨이 새 기준으로 재평가된다.
        let _ = AppContext.shared.settings.currentLogicalDay
        let groups = historyGroups()
        let cancelled = store.cancelledTasks()
        ScrollView {
            LazyVStack(spacing: 0) {
                if groups.isEmpty && cancelled.isEmpty {
                    ListEmptyState(message: "완료 기록이 없습니다", systemImage: "checkmark.circle")
                }
                ForEach(groups, id: \.key) { group in
                    ListSectionHeader(title: group.label, count: group.tasks.count)
                    taskList(group.tasks)
                }
                if !cancelled.isEmpty {
                    ListSectionHeader(
                        title: "취소됨",
                        count: cancelled.count,
                        titleColor: AppTheme.textSecondary
                    )
                    taskList(cancelled)
                }
            }
            .padding(.horizontal, AppTheme.contentPadding)
            .padding(.bottom, 24)
        }
        .background(AppTheme.surface)
        // §17: 메인 리스트 계열에서만 메모 미리보기 opt-in.
        .environment(\.taskRowShowsNotePreview, true)
        .navigationTitle("완료")
    }

    @ViewBuilder
    private func taskList(_ tasks: [TodoTask]) -> some View {
        ForEach(tasks) { task in
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

    private func historyGroups() -> [(key: Date, label: String, tasks: [TodoTask])] {
        let completed = store.completedTasks()
        let grouped = Dictionary(grouping: completed) { task in
            boundary.logicalDate(of: task.completedAt ?? task.createdAt)
        }
        return grouped.keys.sorted(by: >).map { key in
            let tasks = (grouped[key] ?? []).sorted {
                ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
            }
            return (key, dateLabel(key), tasks)
        }
    }

    private func dateLabel(_ day: Date) -> String {
        if day == boundary.logicalToday() { return "오늘" }
        if day == boundary.logicalYesterday() { return "어제" }
        return Self.dayFormatter.string(from: day)
    }

    private func toggleExpand(_ id: UUID) {
        expandedTaskID = (expandedTaskID == id) ? nil : id
    }
}
