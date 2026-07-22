import SwiftUI

/// 날짜 클릭 시 우측에 뜨는 그 날 목록 패널 (PLAN §10.2): 체크·편집 가능한 MainTaskRow 재사용 + 인라인 추가.
struct CalendarDayPanel: View {
    let day: Date
    let store: TaskStore
    let boundary: DayBoundaryService
    let onClose: () -> Void

    @State private var expandedTaskID: UUID?

    var body: some View {
        let tasks = store.tasks(on: day, boundary: boundary)
        VStack(alignment: .leading, spacing: 0) {
            header(count: tasks.count)
            ListRowDivider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ListAddRow(placeholder: "이 날 할 일 추가", onSubmit: addTask)
                    ListRowDivider()
                    if tasks.isEmpty {
                        Text("이 날 할 일이 없습니다")
                            .font(AppTheme.rowMeta)
                            .foregroundStyle(AppTheme.textDisabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    }
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
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 250)
        .background(AppTheme.surfaceSecondary)
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CalendarFormatters.dayPanelTitle.string(from: day))
                    .font(AppTheme.sectionTitle)
                    .foregroundStyle(titleColor)
                Text(relativeLabel)
                    .font(AppTheme.rowMeta)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(AppTheme.badge)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppTheme.divider.opacity(0.8), in: Capsule())
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textDisabled)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var titleColor: Color {
        day == boundary.logicalToday() ? AppTheme.accent : AppTheme.textPrimary
    }

    private var relativeLabel: String {
        let today = boundary.logicalToday()
        if day == today { return "오늘" }
        if day == boundary.logicalYesterday() { return "어제" }
        if day == boundary.calendar.date(byAdding: .day, value: 1, to: today) { return "내일" }
        let diff = boundary.calendar.dateComponents([.day], from: today, to: day).day ?? 0
        return diff < 0 ? "\(-diff)일 전" : "\(diff)일 후"
    }

    private func addTask(_ title: String) {
        let task = TodoTask(title: title)
        task.scheduledDate = boundary.scheduledDateValue(for: day)
        task.sortOrder = (store.tasks.map(\.sortOrder).max() ?? 0) + 1
        store.addTask(task)
    }

    private func toggleExpand(_ id: UUID) {
        expandedTaskID = (expandedTaskID == id) ? nil : id
    }
}
