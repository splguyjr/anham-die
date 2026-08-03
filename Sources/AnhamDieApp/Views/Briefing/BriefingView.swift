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
                .strokeBorder(AppTheme.divider, lineWidth: 1)
        )
        // 브리핑 패널이 선택 팔레트의 명/암을 따르도록(§13.2) — material·시스템 요소가 팔레트와 어긋나지 않게.
        .preferredColorScheme(AppTheme.palette.isDark ? .dark : .light)
    }

    // MARK: - 헤더 / 푸터

    @ViewBuilder
    private func header(total: Int, done: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(AppTheme.accent).frame(width: 10, height: 10)
            Text("오늘의 브리핑").font(.headline).foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Text("\(done)/\(total)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func footer() -> some View {
        HStack {
            Text("esc 닫기")
                .font(.caption2)
                .foregroundStyle(AppTheme.textDisabled)
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
                .foregroundStyle(AppTheme.textSecondary)
            if tasks.isEmpty {
                Text("오늘 예정된 할 일이 없습니다.")
                    .font(.callout)
                    .foregroundStyle(AppTheme.textDisabled)
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
            // 우선순위 = 리딩 엣지 세로 색 막대(§13.4).
            PriorityBar(priority: task.priority)

            Button {
                toggleComplete(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(task.isCompleted ? AppTheme.accent : AppTheme.textDisabled)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(titleColor(completed: task.isCompleted, overdue: overdue))
                    .lineLimit(1)
                // §17: 메모 첫 줄 미리보기 — 메인 리스트와 동일 스타일(rowMeta·textSecondary). 설정 토글만 따른다.
                if let preview = notePreview(task) {
                    Text(preview)
                        .font(AppTheme.rowMeta)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 4)

            // 태그 = 글자 칩(§13.4), 넘치면 "+N".
            BriefingTagCluster(tags: context.store.tags(of: task))

            if task.isRecurring {
                MainRecurrenceBadge(rule: task.recurrence)
            }
            if task.rolloverCount > 0 {
                MainRolloverBadge(count: task.rolloverCount)
            }
            if let due = task.dueDate {
                MainDDayBadge(dDay: boundary.dDay(of: due))
            }
        }
    }

    // MARK: - 어제 못 끝낸 작업 (이월 제안)

    @ViewBuilder
    private func unfinishedSection(_ tasks: [TodoTask], boundary: DayBoundaryService) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("어제 못 끝낸 작업 \(tasks.count)개")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            HStack(spacing: 6) {
                bulkButton("모두 오늘로", AppTheme.accent) {
                    context.rollover.rolloverAllToToday(tasks)
                }
                bulkButton("모두 백로그", AppTheme.textSecondary) {
                    context.rollover.moveAllToBacklog(tasks)
                }
                bulkButton("모두 버리기", AppTheme.overdue) {
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
        .background(AppTheme.textDisabled.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func unfinishedRow(_ task: TodoTask, boundary: DayBoundaryService) -> some View {
        HStack(spacing: 6) {
            // 우선순위 = 리딩 엣지 세로 색 막대(§13.4).
            PriorityBar(priority: task.priority)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.callout)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                // §17: 메모 첫 줄 미리보기 — 이월 제안 행도 동일 스타일. 설정 토글만 따른다.
                if let preview = notePreview(task) {
                    Text(preview)
                        .font(AppTheme.rowMeta)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                HStack(spacing: 6) {
                    if let scheduled = task.scheduledDate {
                        Text(relativeDayLabel(scheduled, boundary: boundary))
                    }
                    if task.rolloverCount > 0 {
                        Text("↺\(task.rolloverCount)")
                    }
                    if task.isRecurring {
                        // 버려도 다음 회차가 생성됨을 알 수 있게 반복 표시 (PLAN §11.5)
                        Label(task.recurrence.displayName, systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(AppTheme.accent)
                    }
                    // 태그 = 글자 칩(§13.4), 좁은 폭이라 최대 1개 + "+N".
                    BriefingTagCluster(tags: context.store.tags(of: task), maxVisible: 1)
                }
                .font(.caption2)
                .foregroundStyle(AppTheme.textDisabled)
            }
            Spacer(minLength: 4)
            iconButton("arrow.right.circle", tint: AppTheme.accent, help: "오늘로 가져오기") {
                context.rollover.rolloverToToday(task)
            }
            iconButton("tray.and.arrow.down", tint: AppTheme.textSecondary, help: "백로그 보류") {
                context.rollover.moveToBacklog(task)
            }
            iconButton("trash", tint: AppTheme.overdue, help: "버리기(취소로 보관)") {
                context.rollover.cancel(task)
            }
        }
    }

    // MARK: - 배지 / 버튼
    //
    // 반복(↻)·이월(↺)·D-day 배지는 공용 Main* 배지(MainRecurrenceBadge/MainRolloverBadge/
    // MainDDayBadge)로 통일해 메인 리스트와 시각 표현을 일치시킨다(§13.4). 지역 재구현 제거.

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
            context.store.notifyChanged()
        } else {
            // 브리핑은 유예 없이 직접 완료를 확정하는 경로 — 확정 직후 반복이면 다음 회차 생성 (PLAN §11.5).
            task.markCompleted(at: context.dayBoundary.now())
            context.store.notifyChanged()
            context.recurrence.scheduleNextOccurrence(after: task)
        }
    }

    // MARK: - 표시 헬퍼

    /// §17 메모 미리보기 첫 줄 — 설정 토글만 따른다(브리핑은 환경값 opt-in 없이 항상 대상). 내용 없으면 nil.
    private func notePreview(_ task: TodoTask) -> String? {
        guard context.settings.showNotePreview else { return nil }
        return NotePreview.firstLine(task.note)
    }

    private func titleColor(completed: Bool, overdue: Bool) -> Color {
        if completed { return AppTheme.textDisabled }
        if overdue { return AppTheme.overdue }
        return AppTheme.textPrimary
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

/// 트레일링 태그 칩 나열 + 오버플로("+N") — 브리핑 행의 좁은 폭 대응(§13.4).
private struct BriefingTagCluster: View {
    let tags: [Tag]
    var maxVisible: Int = 2

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(tags.prefix(maxVisible))) { TagPill($0) }
                if tags.count > maxVisible {
                    Text("+\(tags.count - maxVisible)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }
}
