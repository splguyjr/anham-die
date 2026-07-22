import SwiftUI

/// 브리핑 패널 본문 (PLAN §2.3). 오늘 할 일 + overdue 강조 +
/// "어제 못 끝낸 작업 N개" 이월 제안 섹션(항목별/일괄 오늘로·백로그·버리기).
/// FloatingPanel 안의 NSHostingView로 호스팅된다.
@MainActor
struct BriefingView: View {
    private var context: AppContext { AppContext.shared }

    var body: some View {
        // 관찰 지점: 논리적 하루 경계 통과 시 TriggerService가 갱신 → 재사용되는 브리핑 패널이
        // 새 논리적 오늘 기준(오늘 목록·이월 제안)으로 재평가된다 (PLAN §2.3).
        let _ = context.settings.currentLogicalDay
        let store = context.store
        let boundary = context.dayBoundary
        let today = store.todayTasks(boundary: boundary)
        let unfinished = context.rollover.unfinishedTasksFromPreviousDays()
        let doneCount = today.filter { $0.isCompleted }.count

        VStack(alignment: .leading, spacing: 0) {
            header(total: today.count, done: doneCount)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    todaySection(today, boundary: boundary)
                    if !unfinished.isEmpty {
                        unfinishedSection(unfinished, boundary: boundary)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 420)
            Divider()
            footer()
        }
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 헤더 / 푸터

    @ViewBuilder
    private func header(total: Int, done: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(AppTheme.accent).frame(width: 10, height: 10)
            Text("오늘의 브리핑").font(.headline)
            Spacer()
            Text("\(done)/\(total)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func footer() -> some View {
        HStack {
            Text("esc 닫기")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("닫기") { BriefingController.shared.hide() }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 오늘 할 일

    @ViewBuilder
    private func todaySection(_ tasks: [TodoTask], boundary: DayBoundaryService) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("오늘 할 일")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if tasks.isEmpty {
                Text("오늘 예정된 할 일이 없습니다.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(tasks) { task in
                    todayRow(task, boundary: boundary)
                }
            }
        }
    }

    @ViewBuilder
    private func todayRow(_ task: TodoTask, boundary: DayBoundaryService) -> some View {
        let overdue = !task.isCompleted && (task.dueDate.map { boundary.dDay(of: $0) < 0 } ?? false)
        HStack(spacing: 8) {
            Button {
                toggleComplete(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(task.isCompleted ? AppTheme.accent : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .strikethrough(task.isCompleted)
                .foregroundStyle(titleColor(completed: task.isCompleted, overdue: overdue))
                .lineLimit(1)

            Spacer(minLength: 4)

            if task.rolloverCount > 0 {
                rolloverBadge(task.rolloverCount)
            }
            if let due = task.dueDate {
                dDayBadge(boundary.dDay(of: due))
            }
        }
    }

    // MARK: - 어제 못 끝낸 작업 (이월 제안)

    @ViewBuilder
    private func unfinishedSection(_ tasks: [TodoTask], boundary: DayBoundaryService) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("어제 못 끝낸 작업 \(tasks.count)개")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                bulkButton("모두 오늘로", AppTheme.accent) {
                    context.rollover.rolloverAllToToday(tasks)
                }
                bulkButton("모두 백로그", .gray) {
                    context.rollover.moveAllToBacklog(tasks)
                }
                bulkButton("모두 버리기", .red) {
                    context.rollover.cancelAll(tasks)
                }
            }

            VStack(spacing: 8) {
                ForEach(tasks) { task in
                    unfinishedRow(task, boundary: boundary)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func unfinishedRow(_ task: TodoTask, boundary: DayBoundaryService) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let scheduled = task.scheduledDate {
                        Text(relativeDayLabel(scheduled, boundary: boundary))
                    }
                    if task.rolloverCount > 0 {
                        Text("↺\(task.rolloverCount)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            iconButton("arrow.right.circle", tint: AppTheme.accent, help: "오늘로 가져오기") {
                context.rollover.rolloverToToday(task)
            }
            iconButton("tray.and.arrow.down", tint: .gray, help: "백로그 보류") {
                context.rollover.moveToBacklog(task)
            }
            iconButton("trash", tint: .red, help: "버리기(취소로 보관)") {
                context.rollover.cancel(task)
            }
        }
    }

    // MARK: - 배지 / 버튼

    @ViewBuilder
    private func rolloverBadge(_ count: Int) -> some View {
        HStack(spacing: 1) {
            Image(systemName: "arrow.counterclockwise")
            Text("\(count)")
        }
        .font(.caption2)
        .foregroundStyle(.orange)
    }

    @ViewBuilder
    private func dDayBadge(_ dDay: Int) -> some View {
        let color = dueColor(dDay)
        Text(dDayLabel(dDay))
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func bulkButton(_ title: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(tint)
    }

    @ViewBuilder
    private func iconButton(_ system: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.body)
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - 액션

    private func toggleComplete(_ task: TodoTask) {
        if task.isCompleted {
            task.reactivate()
        } else {
            task.markCompleted(at: context.dayBoundary.now())
        }
        context.store.notifyChanged()
    }

    // MARK: - 표시 헬퍼

    private func titleColor(completed: Bool, overdue: Bool) -> Color {
        if completed { return .secondary }
        if overdue { return AppTheme.overdue }
        return .primary
    }

    private func dueColor(_ dDay: Int) -> Color {
        AppTheme.dueColor(dDay: dDay)
    }

    private func dDayLabel(_ dDay: Int) -> String {
        AppTheme.dDayText(dDay)
    }

    /// scheduledDate가 오늘 기준 며칠 전인지 (음수 = 과거)
    private func relativeDayLabel(_ date: Date, boundary: DayBoundaryService) -> String {
        let diff = boundary.dDay(of: date)
        switch diff {
        case 0: return "오늘"
        case -1: return "어제"
        default:
            if diff < 0 { return "\(-diff)일 전" }
            return "\(diff)일 후"
        }
    }
}
