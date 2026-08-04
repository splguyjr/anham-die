import SwiftUI

// 주간 목표 뷰 공용 조각 (v11 §20.4) — 사이드바 뷰·요약 스트립·기록 행이 공유한다.
// 색·타이포는 AppTheme만 경유(§13.2 동적 테마).

// MARK: - 진행 링 (횟수형)

/// 원형 진행 표시. 초과 달성은 goal.progress에서 1.0로 캡된다(모델 규약). isAchieved면 중앙 체크.
struct WeeklyGoalRing: View {
    let progress: Double
    let isAchieved: Bool
    var size: CGFloat = 30
    var lineWidth: CGFloat = 3.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.divider.opacity(0.5), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AppTheme.accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if isAchieved {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.25), value: progress)
    }
}

// MARK: - 단일형 체크 버튼

/// targetCount 1(단일형) 목표의 체크. 탭하면 0↔1 토글(증감 경유는 호출측이 담당).
struct WeeklyGoalCheckButton: View {
    let isChecked: Bool
    var size: CGFloat = 26
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(isChecked ? AppTheme.accent : Color.clear)
                Circle().strokeBorder(isChecked ? AppTheme.accent : AppTheme.divider, lineWidth: 2)
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ±1 스텝 버튼

/// 직접 증감(§20.2) 원형 버튼. enabled=false면 흐리게·비활성(예: -1 at 0).
struct WeeklyGoalStepButton: View {
    let systemImage: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? AppTheme.accent : AppTheme.textDisabled)
                .frame(width: 24, height: 24)
                .background(Circle().fill(AppTheme.accent.opacity(enabled ? 0.12 : 0.05)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - 루틴 아이콘

/// 루틴(매주 반복) 표식/토글에 공통으로 쓰는 심볼 이름.
let weeklyGoalRoutineSymbol = "arrow.triangle.2.circlepath"

// MARK: - 상태 칩

/// 목표 상태 요약 칩. active는 달성/미달, 그 외는 이월/종료.
struct WeeklyGoalStatusChip: View {
    let goal: WeeklyGoal

    var body: some View {
        let d = descriptor
        Text(d.text)
            .font(AppTheme.badge)
            .foregroundStyle(d.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(d.color.opacity(0.14), in: Capsule())
    }

    private var descriptor: (text: String, color: Color) {
        switch goal.status {
        case .carriedOver: return ("이월", AppTheme.textSecondary)
        case .dropped: return ("종료", AppTheme.textDisabled)
        case .active: return goal.isAchieved
            ? ("달성", AppTheme.accent)
            : ("미달", AppTheme.overdue)
        }
    }
}

// MARK: - 주 범위 라벨

enum WeeklyGoalFormat {
    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d"
        return f
    }()

    /// 주 시작 키 → "M/d ~ M/d" (7일 범위).
    static func weekRange(_ weekStart: Date, calendar: Calendar) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(rangeFormatter.string(from: weekStart)) ~ \(rangeFormatter.string(from: end))"
    }
}
