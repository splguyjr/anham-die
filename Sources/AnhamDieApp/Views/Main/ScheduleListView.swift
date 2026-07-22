import SwiftUI

/// "해야할 일" 기본 뷰 (PLAN §10.1): 지난 할 일 → 오늘 → 내일 → 이후 날짜 섹션을 한 화면 스크롤.
/// 태그 필터 지정 시 해당 태그 태스크만 (사이드바 태그 선택).
/// 스캐폴드 단계 구현 — 행 사용성(§10.6 호버 액션·컨텍스트 메뉴·키보드)은 담당 모듈이 확장한다.
struct ScheduleListView: View {
    var tagFilter: Tag? = nil

    @State private var expandedTaskID: UUID?

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d (E)"
        return f
    }()

    var body: some View {
        let sections = store.scheduleSections(boundary: boundary, tagFilter: tagFilter)
        ScrollView {
            LazyVStack(spacing: 0) {
                ListAddRow(placeholder: addPlaceholder, onSubmit: addTask)
                ListRowDivider()
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    ListSectionHeader(
                        title: sectionTitle(section.day),
                        count: section.tasks.count,
                        titleColor: sectionColor(section.day)
                    )
                    if section.tasks.isEmpty {
                        Text("할 일 없음")
                            .font(AppTheme.rowMeta)
                            .foregroundStyle(AppTheme.textDisabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                    ForEach(section.tasks) { task in
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
            }
            .padding(.horizontal, AppTheme.contentPadding)
            .padding(.bottom, 24)
        }
        .background(AppTheme.surface)
        .navigationTitle(tagFilter.map { "#\($0.name)" } ?? "해야할 일")
    }

    private var addPlaceholder: String {
        tagFilter.map { "#\($0.name)에 오늘 할 일 추가" } ?? "오늘 할 일 추가"
    }

    private func sectionTitle(_ day: Date?) -> String {
        guard let day else { return "🔴 지난 할 일" }
        let base = Self.dayFormatter.string(from: day)
        let today = boundary.logicalToday()
        if day == today { return "오늘 \(base)" }
        if day == boundary.calendar.date(byAdding: .day, value: 1, to: today) {
            return "내일 \(base)"
        }
        return base
    }

    private func sectionColor(_ day: Date?) -> Color {
        guard let day else { return AppTheme.overdue }
        return day == boundary.logicalToday() ? AppTheme.accent : AppTheme.textPrimary
    }

    private func addTask(_ title: String) {
        let task = TodoTask(title: title)
        task.scheduledDate = boundary.scheduledToday()
        if let tag = tagFilter {
            task.tagIDs = [tag.id]
        }
        task.sortOrder = (store.tasks.map(\.sortOrder).max() ?? 0) + 1
        store.addTask(task)
    }

    private func toggleExpand(_ id: UUID) {
        expandedTaskID = (expandedTaskID == id) ? nil : id
    }
}
