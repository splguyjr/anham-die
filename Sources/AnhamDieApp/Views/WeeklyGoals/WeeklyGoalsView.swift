import SwiftUI

/// 사이드바 '주간 목표' 뷰 (v11 §20.4 ①).
/// 상단: 추가 행(제목·횟수·루틴) → 이번 주 목표 목록(진행 링/바·단일형 체크·[오늘 하기]·직접 ±1·
/// 루틴 토글·편집/삭제). 하단: 지난 주 기록(주별 그룹·달성률, 읽기 전용).
/// 데이터 원천은 store(@Observable) — 목표/카운트 변경 시 자동 재평가된다.
struct WeeklyGoalsView: View {
    @State private var newTitle = ""
    @State private var newTarget = 1
    @State private var newRoutine = false
    @State private var editingGoal: WeeklyGoal?
    @State private var pendingDelete: WeeklyGoal?

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }

    var body: some View {
        // 관찰: 논리적 하루/주 경계 통과 시 '이번 주' 기준이 새 주로 재평가된다.
        let _ = AppContext.shared.settings.currentLogicalDay
        let currentWeek = boundary.currentWeekStart()
        let currentGoals = store.weeklyGoals(forWeek: currentWeek, boundary: boundary)
        // 지난 주 기록 = 이번 주를 제외한 주별 그룹(최근 주 먼저).
        let history = store.weeklyGoalsGroupedByWeek(boundary: boundary)
            .filter { $0.week != currentWeek }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                thisWeekHeader(count: currentGoals.count, week: currentWeek)

                WeeklyGoalAddRow(
                    title: $newTitle, target: $newTarget, routine: $newRoutine, onAdd: addGoal
                )
                ListRowDivider()

                if currentGoals.isEmpty {
                    ListEmptyState(message: "이번 주 목표가 없습니다", systemImage: "target")
                } else {
                    ForEach(currentGoals) { goal in
                        WeeklyGoalRow(
                            goal: goal,
                            store: store,
                            boundary: boundary,
                            hasTodayTask: hasTodayLinkedTask(goal),
                            onEdit: { editingGoal = goal },
                            onDelete: { pendingDelete = goal }
                        )
                        ListRowDivider()
                    }
                }

                if !history.isEmpty {
                    historySection(history)
                }
            }
            .padding(.horizontal, AppTheme.contentPadding)
            .padding(.bottom, 24)
        }
        .background(AppTheme.surface)
        .navigationTitle("주간 목표")
        .sheet(item: $editingGoal) { goal in
            WeeklyGoalEditSheet(goal: goal, store: store)
        }
        .confirmationDialog(
            "이 목표를 삭제할까요?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { goal in
            Button("삭제", role: .destructive) { store.removeWeeklyGoal(goal) }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("연결된 오늘 할 일은 남지만 주간 배지는 사라집니다.")
        }
    }

    // MARK: - 이번 주 헤더

    @ViewBuilder
    private func thisWeekHeader(count: Int, week: Date) -> some View {
        ListSectionHeader(title: "이번 주 목표", count: count)
        Text(WeeklyGoalFormat.weekRange(week, calendar: boundary.calendar))
            .font(AppTheme.rowMeta)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.bottom, 8)
    }

    // MARK: - 지난 주 기록 (읽기 전용)

    @ViewBuilder
    private func historySection(_ groups: [(week: Date, goals: [WeeklyGoal])]) -> some View {
        ForEach(groups, id: \.week) { group in
            WeeklyGoalHistoryHeader(
                range: WeeklyGoalFormat.weekRange(group.week, calendar: boundary.calendar),
                achieved: group.goals.filter(\.isAchieved).count,
                total: group.goals.count
            )
            ForEach(group.goals) { goal in
                WeeklyGoalHistoryRow(goal: goal)
                ListRowDivider()
            }
        }
    }

    // MARK: - 액션

    private func addGoal() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let goal = WeeklyGoal(
            title: title,
            targetCount: max(1, newTarget),
            weekKey: boundary.scheduledDateValue(for: boundary.currentWeekStart()),
            isRoutine: newRoutine
        )
        store.addWeeklyGoal(goal)
        newTitle = ""
        newTarget = 1
        newRoutine = false
    }

    /// 오늘에 연결된 활성 task가 이미 있는가 (버튼 상태 표시용, createLinkedTask 멱등 기준과 동일).
    private func hasTodayLinkedTask(_ goal: WeeklyGoal) -> Bool {
        let today = boundary.logicalToday()
        return store.tasks.contains { task in
            task.isActive && task.weeklyGoalID == goal.id
                && task.scheduledDate.map { boundary.logicalDay(ofStored: $0) } == today
        }
    }
}

// MARK: - 기록 헤더

private struct WeeklyGoalHistoryHeader: View {
    let range: String
    let achieved: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(range)
                .font(AppTheme.sectionTitle)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Text("달성 \(achieved)/\(total)")
                .font(AppTheme.badge)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(AppTheme.textSecondary.opacity(0.12), in: Capsule())
        }
        .padding(.top, AppTheme.sectionSpacing)
        .padding(.bottom, 6)
    }
}

// MARK: - 기록 행 (읽기 전용)

private struct WeeklyGoalHistoryRow: View {
    let goal: WeeklyGoal

    private var isSingle: Bool { goal.targetCount <= 1 }

    var body: some View {
        HStack(spacing: AppTheme.rowSpacing) {
            if isSingle {
                Image(systemName: goal.isAchieved ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(goal.isAchieved ? AppTheme.accent : AppTheme.textDisabled)
                    .frame(width: 26)
            } else {
                WeeklyGoalRing(progress: goal.progress, isAchieved: goal.isAchieved, size: 26, lineWidth: 3)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(goal.title)
                        .font(AppTheme.rowTitle)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                    if goal.isRoutine {
                        Image(systemName: weeklyGoalRoutineSymbol)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .help("루틴")
                    }
                }
                if !isSingle {
                    Text("\(goal.currentCount)/\(goal.targetCount)")
                        .font(AppTheme.rowMeta)
                        .foregroundStyle(AppTheme.textDisabled)
                }
            }

            Spacer(minLength: 8)

            WeeklyGoalStatusChip(goal: goal)
        }
        .padding(.vertical, AppTheme.rowVerticalPadding)
        .frame(minHeight: AppTheme.rowMinHeight)
    }
}
