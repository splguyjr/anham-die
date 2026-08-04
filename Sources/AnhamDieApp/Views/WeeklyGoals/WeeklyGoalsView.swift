import SwiftUI

/// v11 주간 목표 뷰 스텁 (§20.4) — 사이드바 '주간 목표' 모듈이 본 구현으로 교체한다.
/// 예정 기능: 추가/편집(제목·횟수·루틴 토글)·진행 링·[오늘 하기]·직접 ±1·지난 주 기록.
/// 데이터 접근: store.weeklyGoals(forWeek:boundary:)·increment/decrementGoalCount·
/// createLinkedTask(goal:boundary:)·AppContext.shared.weeklyReview.
struct WeeklyGoalsView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "target")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.accent)
            Text("주간 목표")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("준비 중입니다")
                .font(.callout)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}
