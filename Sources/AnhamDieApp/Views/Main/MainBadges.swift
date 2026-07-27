import SwiftUI

/// 체크박스 (완료/미완료 토글). Scribble 스타일의 원형 체크.
struct MainCheckbox: View {
    let isDone: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isDone ? MainTheme.accent : MainTheme.inkTertiary)
        }
        .buttonStyle(.plain)
    }
}

/// D-day 배지. 색상은 due까지 남은 일수로 결정 (PLAN §3.1).
struct MainDDayBadge: View {
    let dDay: Int

    var body: some View {
        let color = MainTheme.dueColor(dDay: dDay)
        Text(MainTheme.dDayText(dDay))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// 이월 배지 (↺n). rolloverCount > 0 일 때만 표시.
struct MainRolloverBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .bold))
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(MainTheme.inkSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        // 캡슐 채움은 divider 재사용 금지 — 하이콘트라스트의 divider는 '굵은 구분선' 목적의
        // 근흑(0.10)이라 채움으로 쓰면 textSecondary(0.12) 글자와 겹친다(실측 1.79:1).
        // 글자색 12% 틴트로 채우면 어떤 팔레트(커스텀 포함)에서도 글자-채움 대비가
        // 글자-표면 대비를 따라간다(9종 실측 4.90~13.03:1, D-day 14%·반복 12% 틴트와 동일 관례).
        .background(MainTheme.inkSecondary.opacity(0.12), in: Capsule())
    }
}

/// 반복 배지 (↻ + 규칙명). task.isRecurring일 때만 표시 (PLAN §11.5).
struct MainRecurrenceBadge: View {
    let rule: RecurrenceRule

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9, weight: .bold))
            Text(rule.displayName)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(MainTheme.accent)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(MainTheme.accent.opacity(0.12), in: Capsule())
        .help(rule.displayName)
    }
}

/// 우선순위/태그 색 점.
struct MainColorDot: View {
    let color: Color
    var size: CGFloat = AppTheme.dotSize

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}
