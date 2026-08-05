import SwiftUI

/// '해야할 일' 상단 요약 카드 (v11 §20.4 ②) — 이번 주 진행 목표를 콤팩트 스트립으로 보여준다.
/// 접힘 상태는 UserDefaults("weeklyStripCollapsed")에 영속(AppSettings 미변경 — 소유 경계 유지).
/// 진행 중 목표가 하나도 없으면 카드 자체를 렌더하지 않는다(빈 카드로 목록을 밀어내지 않음).
struct WeeklyGoalSummaryCard: View {
    @AppStorage("weeklyStripCollapsed") private var collapsed = false

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }

    var body: some View {
        let _ = AppContext.shared.settings.currentLogicalDay
        let goals = store.weeklyGoals(forWeek: boundary.currentWeekStart(), boundary: boundary)
            .filter { $0.status == .active }
        if !goals.isEmpty {
            card(goals: goals)
        }
    }

    private func card(goals: [WeeklyGoal]) -> some View {
        let achieved = goals.filter(\.isAchieved).count
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("이번 주 목표")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("\(achieved)/\(goals.count)")
                        .font(AppTheme.badge)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.textSecondary.opacity(0.12), in: Capsule())
                    Spacer()
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(collapsed ? "펼치기" : "접기")

            if !collapsed {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(goals) { goal in
                            WeeklyGoalMiniPill(
                                goal: goal,
                                hasTodayTask: store.hasTodayLink(goal: goal, boundary: boundary),
                                onToggle: { store.toggleTodayLink(goal: goal, boundary: boundary) }
                            )
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .fill(AppTheme.surfaceSecondary)
        )
        .padding(.top, 14)
    }
}

// MARK: - 미니 목표 칩

/// 스트립 한 칸 — 단일형은 체크 아이콘, 횟수형은 미니 링 + n/m.
/// 클릭 시 [오늘 하기] 공용 토글(§21.9): 오늘에 배치되어 있으면 해제, 없으면 배치.
/// 오늘 배치 상태(hasTodayTask)는 우측 배지·강조 테두리로 표시.
private struct WeeklyGoalMiniPill: View {
    let goal: WeeklyGoal
    /// 오늘에 연결된 미완료 task가 있는가 (선택 상태 표시용, 부모가 store에서 산출).
    let hasTodayTask: Bool
    let onToggle: () -> Void

    private var isSingle: Bool { goal.targetCount <= 1 }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                if isSingle {
                    Image(systemName: goal.isAchieved ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(goal.isAchieved ? AppTheme.accent : AppTheme.textDisabled)
                } else {
                    WeeklyGoalRing(progress: goal.progress, isAchieved: goal.isAchieved, size: 18, lineWidth: 2.5)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(goal.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    if !isSingle {
                        Text("\(goal.currentCount)/\(goal.targetCount)")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                Image(systemName: hasTodayTask ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hasTodayTask ? AppTheme.accent : AppTheme.textDisabled)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hasTodayTask ? AppTheme.accent.opacity(0.12) : AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        hasTodayTask ? AppTheme.accent.opacity(0.6) : AppTheme.divider.opacity(0.6),
                        lineWidth: 1
                    )
            )
            .frame(maxWidth: 160)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(hasTodayTask ? "오늘 목록에서 빼기" : "오늘 할 일로 추가")
    }
}
