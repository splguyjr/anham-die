import AppIntents
import SwiftUI
import WidgetKit

/// 패밀리별 최대 표시 개수 (PLAN §3.3: small 2 / medium 5 / large 10).
private func maxRows(for family: WidgetFamily) -> Int {
    switch family {
    case .systemSmall: return 2
    case .systemMedium: return 5
    case .systemLarge: return 10
    default: return 5
    }
}

struct AnhamDieWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var snapshot: TodaySnapshot { entry.snapshot }
    private var hasOverdue: Bool { snapshot.items.contains(where: \.isOverdue) }

    var body: some View {
        let limit = maxRows(for: family)
        let visible = Array(snapshot.items.prefix(limit))
        let overflow = snapshot.totalCount - visible.count

        VStack(alignment: .leading, spacing: family == .systemSmall ? 5 : 7) {
            header
            if snapshot.items.isEmpty {
                emptyState
            } else {
                ForEach(visible) { task in
                    TaskRow(task: task, compact: family == .systemSmall)
                }
                if overflow > 0 {
                    Text("+\(overflow)개 더")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(hasOverdue ? Color.red : Color.accentColor)
                .frame(width: 8, height: 8)
            Text("오늘 할 일")
                .font(.system(size: family == .systemSmall ? 12 : 13, weight: .semibold))
            Spacer(minLength: 4)
            Text("\(snapshot.completedCount)/\(snapshot.totalCount)")
                .font(.system(size: family == .systemSmall ? 12 : 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.bottom, 1)
    }

    private var emptyState: some View {
        Text("할 일이 없습니다")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

private struct TaskRow: View {
    let task: WidgetTask
    let compact: Bool

    var body: some View {
        HStack(spacing: 7) {
            Button(intent: ToggleTaskIntent(taskID: task.id)) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: compact ? 14 : 15))
                    .foregroundStyle(task.isCompleted ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            if let hex = task.priorityColorHex, let dot = Color(hex: hex), !task.isCompleted {
                Circle().fill(dot).frame(width: 6, height: 6)
            }

            Text(task.title)
                .font(.system(size: compact ? 12 : 13))
                .lineLimit(1)
                .strikethrough(task.isCompleted, color: .secondary)
                .foregroundStyle(titleColor)

            Spacer(minLength: 4)

            if let dDay = task.dDayText, !task.isCompleted {
                Text(dDay)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var titleColor: Color {
        if task.isCompleted { return .secondary }
        if task.isOverdue { return .red }
        return .primary
    }
}

extension Color {
    /// "#RRGGBB" 16진 문자열 → Color. 형식이 어긋나면 nil.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
