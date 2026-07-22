import SwiftUI

/// 월간 그리드의 한 날짜 셀 (PLAN §10.2): 날짜 숫자 + task 제목 1~2개 + "+N개".
/// 각 task 제목 칩은 .draggable — 다른 셀로 드래그하면 scheduledDate가 바뀐다.
/// overdue(지난 날짜의 미완료)는 빨강, 오늘 셀은 강조, 셀 밖의 달은 흐리게.
struct CalendarDayCell: View {
    let day: Date
    let tasks: [TodoTask]
    let isInMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isDropTarget: Bool
    let isPast: Bool
    let cellHeight: CGFloat
    let calendar: Calendar
    let onSelect: () -> Void

    private let maxVisible = 2

    private var dayNumber: Int { calendar.component(.day, from: day) }
    private var weekday: Int { calendar.component(.weekday, from: day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            numberRow
            taskList
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: cellHeight, maxHeight: cellHeight, alignment: .topLeading)
        .background(cellBackground)
        .overlay(dropBorder)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .opacity(isInMonth ? 1 : 0.4)
    }

    private var numberRow: some View {
        HStack {
            ZStack {
                if isToday {
                    Circle().fill(AppTheme.accent).frame(width: 20, height: 20)
                }
                Text("\(dayNumber)")
                    .font(.system(size: 12, weight: isToday ? .bold : .medium))
                    .foregroundStyle(numberColor)
            }
            .frame(width: 20, height: 20)
            Spacer()
        }
    }

    @ViewBuilder
    private var taskList: some View {
        ForEach(tasks.prefix(maxVisible)) { task in
            Text(task.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(taskColor(task))
                .strikethrough(task.isCompleted, color: AppTheme.textDisabled)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(taskChipBackground(task), in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .draggable(CalendarTaskDrag(taskID: task.id))
        }
        if tasks.count > maxVisible {
            Text("+\(tasks.count - maxVisible)개")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    private var numberColor: Color {
        if isToday { return .white }
        let base = isInMonth ? AppTheme.textPrimary : AppTheme.textDisabled
        return CalendarPalette.weekdayColor(weekday, base: base)
    }

    /// task 제목 색: 완료=비활성색, overdue(지난 날짜의 미완료)=빨강, 그 외 기본색.
    private func taskColor(_ task: TodoTask) -> Color {
        if task.isCompleted { return AppTheme.textDisabled }
        if isPast { return AppTheme.overdue }
        return AppTheme.textPrimary
    }

    private func taskChipBackground(_ task: TodoTask) -> Color {
        if task.isCompleted { return .clear }
        if isPast { return AppTheme.overdue.opacity(0.12) }
        return AppTheme.accent.opacity(0.08)
    }

    private var cellBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius)
            .fill(fillColor)
    }

    private var fillColor: Color {
        if isDropTarget { return AppTheme.accent.opacity(0.18) }
        if isSelected { return AppTheme.selectedBackground }
        if isToday { return AppTheme.accent.opacity(0.06) }
        return .clear
    }

    @ViewBuilder
    private var dropBorder: some View {
        RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius)
            .strokeBorder(
                isDropTarget ? AppTheme.accent : (isSelected ? AppTheme.accent.opacity(0.4) : .clear),
                lineWidth: isDropTarget ? 2 : 1
            )
    }
}
