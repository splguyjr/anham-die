import SwiftUI

/// 주간 뷰 (PLAN §12.1): 일~토 7열, 각 열은 그날 task를 세로로 나열(스크롤).
/// 열 간 드래그 = scheduledDate 변경(CalendarTaskDrag·자정 날짜 키 규약), 오늘 열 강조.
/// 상세 편집은 열/칩을 탭해 우측 날짜 패널을 여는 쪽으로 위임한다(월간과 동일 상호작용).
struct CalendarWeekView: View {
    let anchor: Date
    let today: Date
    let store: TaskStore
    let boundary: DayBoundaryService
    let selectedDay: Date?
    let onSelectDay: (Date) -> Void

    @State private var dropTargetDay: Date?

    private var calendar: Calendar { boundary.calendar }

    var body: some View {
        let columns = store.weekColumns(containing: anchor, boundary: boundary)
        VStack(spacing: 0) {
            // §20.4 ③: 그 주의 주간 목표 진행 스트립(현재 주=라이브, 과거/미래 주=해당 주 기록/비어있음).
            goalStrip
            Divider()
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.element.day) { index, col in
                    if index > 0 { Divider() }
                    column(day: col.day, tasks: col.tasks)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 주간 목표 스트립 (§20.4 ③)

    /// 표시 중인 주의 논리적 주 키는 boundary.weekStart(ofDay:)로 구한다(달력 일요일 시작과 다른 논리적 주).
    /// 같은 쿼리가 현재/과거/미래를 모두 처리 — 현재 주는 store 관찰로 라이브 갱신, 그 외는 해당 주 기록/빈 상태.
    private var goalStrip: some View {
        let weekStart = boundary.weekStart(ofDay: anchor)
        let goals = store.weeklyGoals(forWeek: weekStart, boundary: boundary)
        let isCurrentWeek = weekStart == boundary.currentWeekStart()
        let achieved = goals.filter(\.isAchieved).count
        return HStack(spacing: 8) {
            Image(systemName: "target")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
            if goals.isEmpty {
                Text(isCurrentWeek ? "이번 주 목표 없음" : "이 주 목표 기록 없음")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textDisabled)
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(goals) { goal in
                            goalChip(goal)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(achieved)/\(goals.count) 달성")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surfaceSecondary)
    }

    private func goalChip(_ goal: WeeklyGoal) -> some View {
        HStack(spacing: 5) {
            GoalRing(progress: goal.progress, achieved: goal.isAchieved)
            Text(goal.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(goal.isAchieved ? AppTheme.textSecondary : AppTheme.textPrimary)
                .lineLimit(1)
            Text("\(goal.currentCount)/\(goal.targetCount)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(AppTheme.accent.opacity(goal.isAchieved ? 0.14 : 0.08), in: Capsule())
        .help("\(goal.title) · \(goal.currentCount)/\(goal.targetCount)\(goal.isRoutine ? " · 루틴" : "")")
    }

    // MARK: - 열

    private func column(day: Date, tasks: [TodoTask]) -> some View {
        let isToday = day == today
        let isPast = day < today
        let isSelected = selectedDay == day
        let isDropTarget = dropTargetDay == day

        return VStack(spacing: 0) {
            columnHeader(day: day, isToday: isToday, count: tasks.count)
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    if tasks.isEmpty {
                        Text("—")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textDisabled)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                    ForEach(tasks) { task in
                        taskChip(task, day: day, isPast: isPast)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(columnBackground(isToday: isToday, isSelected: isSelected, isDropTarget: isDropTarget))
        .contentShape(Rectangle())
        .onTapGesture { onSelectDay(day) }
        .dropDestination(for: CalendarTaskDrag.self) { items, _ in
            reschedule(items, to: day)
        } isTargeted: { targeted in
            if targeted {
                dropTargetDay = day
            } else if dropTargetDay == day {
                dropTargetDay = nil
            }
        }
    }

    private func columnHeader(day: Date, isToday: Bool, count: Int) -> some View {
        let weekday = calendar.component(.weekday, from: day)
        return HStack(spacing: 6) {
            Text(weekdaySymbol(weekday))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CalendarPalette.weekdayColor(weekday, base: AppTheme.textSecondary))
            ZStack {
                if isToday {
                    Circle().fill(AppTheme.accent).frame(width: 22, height: 22)
                }
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 13, weight: isToday ? .bold : .semibold))
                    .foregroundStyle(isToday ? .white : CalendarPalette.weekdayColor(weekday, base: AppTheme.textPrimary))
            }
            .frame(width: 22, height: 22)
            Spacer(minLength: 0)
            if count > 0 {
                Text("\(count)")
                    .font(AppTheme.badge)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private func taskChip(_ task: TodoTask, day: Date, isPast: Bool) -> some View {
        HStack(alignment: .top, spacing: 5) {
            if task.priority != .normal {
                MainColorDot(color: priorityDotColor(task), size: 6)
                    .padding(.top, 4)
            }
            Text(task.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(chipTextColor(task, isPast: isPast))
                .strikethrough(task.isCompleted, color: AppTheme.textDisabled)
                // §12.1 주간 칩도 폭이 좁으므로 최대 2줄 줄바꿈 + 넘치면 말줄임 + 호버 툴팁.
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(chipBackground(task, isPast: isPast), in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .help(task.title)
        .onTapGesture { onSelectDay(day) }
        .draggable(CalendarTaskDrag(taskID: task.id))
    }

    // MARK: - 색상

    /// 주간 셀 우선순위 점 — 모노 팔레트면 무채 농도(resolvedPriorityStyle), 비-모노는 v4 점 색 그대로(회귀 금지)(§15.2).
    private func priorityDotColor(_ task: TodoTask) -> Color {
        AppTheme.palette.monochrome
            ? AppTheme.resolvedPriorityStyle(task.priority).color
            : AppTheme.priorityColor(task.priority)
    }

    private func chipTextColor(_ task: TodoTask, isPast: Bool) -> Color {
        if task.isCompleted { return AppTheme.textDisabled }
        if isPast { return AppTheme.overdue }
        return AppTheme.textPrimary
    }

    private func chipBackground(_ task: TodoTask, isPast: Bool) -> Color {
        if task.isCompleted { return AppTheme.surface.opacity(0.6) }
        if isPast { return AppTheme.overdue.opacity(0.12) }
        return AppTheme.accent.opacity(0.08)
    }

    private func columnBackground(isToday: Bool, isSelected: Bool, isDropTarget: Bool) -> Color {
        if isDropTarget { return AppTheme.accent.opacity(0.16) }
        if isSelected { return AppTheme.selectedBackground }
        if isToday { return AppTheme.accent.opacity(0.05) }
        return .clear
    }

    // MARK: - 액션

    /// 열 간 드롭 = scheduledDate 변경 (자정 날짜 키 규약).
    private func reschedule(_ items: [CalendarTaskDrag], to day: Date) -> Bool {
        dropTargetDay = nil
        guard let item = items.first, let task = store.task(withID: item.taskID) else { return false }
        task.scheduledDate = boundary.scheduledDateValue(for: day)
        store.notifyChanged()
        return true
    }

    private func weekdaySymbol(_ weekday: Int) -> String {
        ["일", "월", "화", "수", "목", "금", "토"][(weekday - 1 + 7) % 7]
    }
}

/// 주간 목표 진행 링 (스트립 칩용) — trim 원호. 달성 시 체크 표식.
private struct GoalRing: View {
    let progress: Double
    let achieved: Bool
    var size: CGFloat = 13

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.textSecondary.opacity(0.22), lineWidth: 2.5)
            Circle()
                // 진행 0에서도 시작점이 보이도록 최소 원호를 남긴다.
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if achieved {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
    }
}
