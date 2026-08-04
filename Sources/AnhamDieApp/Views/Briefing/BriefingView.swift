import SwiftUI

/// 브리핑 패널 본문 (PLAN §2.3). 오늘 할 일 + overdue 강조 +
/// "어제 못 끝낸 작업 N개" 이월 제안 섹션(항목별/일괄 오늘로·백로그·버리기).
/// FloatingPanel 안의 NSHostingView로 호스팅된다.
@MainActor
struct BriefingView: View {
    private var context: AppContext { AppContext.shared }

    // '지난주 리뷰' 노출은 논리적 하루 변화(= 새 브리핑 사이클)마다 재판정한다.
    // 브리핑 패널은 재사용(rootView 교체)돼 @State가 유지·onAppear가 다시 안 뜨므로,
    // 창 생명주기 대신 관찰값 currentLogicalDay 변화에 onChange로 건다(주당 1회 정합).
    /// 이번 마운트에서 리뷰를 노출 중인가 — 후보 처리 중 섹션이 사라지지 않도록 세션 상태로 유지.
    @State private var reviewVisible = false
    /// 현재 리뷰 세션이 가리키는 논리적 주 — 주가 바뀌면 heldGoalIDs를 리셋한다.
    @State private var reviewSessionWeek: Date?
    /// 이번 세션에서 '보류'한 후보 id — 상태는 그대로 두되(다음 주 리뷰에 재등장) 현재 목록에서만 숨긴다.
    @State private var heldGoalIDs: Set<UUID> = []
    /// 리뷰 활성화 시점에 이월 후보가 있었는가 — 후보를 모두 처리한 뒤의 안내 문구 분기용.
    @State private var reviewHadCandidates = false

    var body: some View {
        // 관찰 지점: 논리적 하루 경계 통과 시 TriggerService가 갱신 → 재사용되는 브리핑 패널이
        // 새 논리적 오늘 기준(오늘 목록·이월 제안)으로 재평가된다 (PLAN §2.3).
        let _ = context.settings.currentLogicalDay
        let store = context.store
        let boundary = context.dayBoundary
        let today = store.todayTasks(boundary: boundary)
        let unfinished = context.rollover.unfinishedTasksFromPreviousDays()
        let doneCount = today.filter { $0.isCompleted }.count
        let currentWeek = boundary.currentWeekStart()
        // 이번 주 진행 미니 요약(§20.4)은 이번 주 active 목표만 — 이월/종료된 기록은 사이드바 몫.
        let weekGoals = store.weeklyGoals(forWeek: currentWeek, boundary: boundary)
            .filter { $0.status == .active }

        VStack(alignment: .leading, spacing: 0) {
            header(total: today.count, done: doneCount)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    todaySection(today, boundary: boundary)
                    if !unfinished.isEmpty {
                        unfinishedSection(unfinished, boundary: boundary)
                    }
                    if reviewVisible {
                        weekReviewSection(currentWeek: currentWeek, boundary: boundary)
                    }
                    if !weekGoals.isEmpty {
                        weeklyMiniSummary(weekGoals)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 420)
            Divider()
            footer()
        }
        .frame(width: 360)
        // 첫 평가(initial) + 논리적 하루/주 변화마다 리뷰 노출을 재판정한다.
        .onChange(of: context.settings.currentLogicalDay, initial: true) { _, _ in
            evaluateWeekReview(boundary: boundary)
        }
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

    // MARK: - 지난주 리뷰 (주 전환, §20.3)

    /// 새 브리핑 사이클(첫 평가·하루/주 변화)마다: 이번 주 리뷰 미노출 + 리뷰할 내용(후보 또는
    /// 지난주 목표)이 있으면 노출하고 즉시 '노출함'으로 기록한다(주당 1회). 마킹 후 같은 주의 다음
    /// 브리핑(다음 날)엔 shouldPresentWeekReview()가 false라 숨는다 — '보류'한 후보는 다음 주에 재등장.
    private func evaluateWeekReview(boundary: DayBoundaryService) {
        let currentWeek = boundary.currentWeekStart()
        // 주가 바뀌면 지난 주의 '보류' 숨김을 초기화한다.
        if reviewSessionWeek != currentWeek {
            heldGoalIDs = []
            reviewSessionWeek = currentWeek
        }
        let review = context.weeklyReview
        let candidates = review.carryOverCandidates()
        let lastWeek = boundary.previousWeekStart(before: currentWeek)
        let lastWeekGoals = context.store.weeklyGoals(forWeek: lastWeek, boundary: boundary)
        if review.shouldPresentWeekReview() && (!candidates.isEmpty || !lastWeekGoals.isEmpty) {
            reviewHadCandidates = !candidates.isEmpty
            review.markWeekReviewed()
            reviewVisible = true
        } else {
            reviewVisible = false
        }
    }

    @ViewBuilder
    private func weekReviewSection(currentWeek: Date, boundary: DayBoundaryService) -> some View {
        // 후보는 매 렌더 재조회 — 이월/종료된 목표는 자연히 빠지고, 보류는 heldGoalIDs로만 숨긴다.
        let candidates = context.weeklyReview.carryOverCandidates()
            .filter { !heldGoalIDs.contains($0.id) }
        let lastWeek = boundary.previousWeekStart(before: currentWeek)
        let lastWeekGoals = context.store.weeklyGoals(forWeek: lastWeek, boundary: boundary)
        let achieved = lastWeekGoals.filter { $0.isAchieved }.count

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(AppTheme.accent)
                Text("지난주 리뷰")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if !lastWeekGoals.isEmpty {
                Text("지난주 목표 \(lastWeekGoals.count)개 · 달성 \(achieved) ✓")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if candidates.isEmpty {
                Text(reviewClearedMessage(lastWeekGoals: lastWeekGoals, achieved: achieved))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textDisabled)
            } else {
                Text("미달 목표 \(candidates.count)개 — 이번 주로 이어갈까요?")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textDisabled)
                HStack(spacing: 6) {
                    bulkButton("모두 이번 주로", AppTheme.accent) {
                        for goal in candidates { context.weeklyReview.carryOver(goal) }
                    }
                    bulkButton("모두 보류", AppTheme.textSecondary) {
                        heldGoalIDs.formUnion(candidates.map(\.id))
                    }
                    bulkButton("모두 종료", AppTheme.overdue) {
                        for goal in candidates { context.weeklyReview.drop(goal) }
                    }
                }
                VStack(spacing: 8) {
                    ForEach(candidates) { goal in
                        reviewRow(goal)
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.textDisabled.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 후보가 없을 때의 안내 문구 — 처음부터 미달이 없었는지(달성 축하) vs 방금 모두 정리했는지 구분.
    private func reviewClearedMessage(lastWeekGoals: [WeeklyGoal], achieved: Int) -> String {
        if reviewHadCandidates { return "미달 목표를 모두 정리했어요." }
        if !lastWeekGoals.isEmpty && achieved == lastWeekGoals.count { return "지난주 목표를 모두 달성했어요 🎉" }
        return "이월할 미달 목표가 없어요."
    }

    @ViewBuilder
    private func reviewRow(_ goal: WeeklyGoal) -> some View {
        HStack(spacing: 6) {
            BriefingGoalRing(progress: goal.progress)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.callout)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text("\(goal.currentCount)/\(goal.targetCount) · 잔여 \(goal.remainingCount)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textDisabled)
            }
            Spacer(minLength: 4)
            iconButton("arrow.right.circle", tint: AppTheme.accent, help: "이번 주로 이어가기 (잔여량만)") {
                context.weeklyReview.carryOver(goal)
            }
            iconButton("clock.arrow.circlepath", tint: AppTheme.textSecondary, help: "보류 (다음 주 리뷰에 다시)") {
                heldGoalIDs.insert(goal.id)
            }
            iconButton("xmark.circle", tint: AppTheme.overdue, help: "종료 (기록만 남김)") {
                context.weeklyReview.drop(goal)
            }
        }
    }

    // MARK: - 이번 주 진행 미니 요약 (§20.4)

    @ViewBuilder
    private func weeklyMiniSummary(_ goals: [WeeklyGoal]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("이번 주 목표")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            ForEach(goals.prefix(3)) { goal in
                HStack(spacing: 8) {
                    BriefingGoalRing(progress: goal.progress)
                    Text(goal.title)
                        .font(.callout)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(goal.currentCount)/\(goal.targetCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                    if goal.isAchieved {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            // "더보기" 관례(§20.4): 브리핑은 이동 대상이 없어 남은 개수만 안내한다(사이드바 주간 목표 뷰가 전체).
            if goals.count > 3 {
                Text("외 \(goals.count - 3)개 더 · 사이드바에서 보기")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textDisabled)
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
            // 유예(CompletionGraceController) 우회 경로라 연결 주간 목표 -1을 직접 보정한다 (§20.2).
            if let goalID = task.weeklyGoalID {
                context.store.decrementGoalCount(id: goalID)
            }
        } else {
            // 브리핑은 유예 없이 직접 완료를 확정하는 경로 — 확정 직후 반복이면 다음 회차 생성 (PLAN §11.5).
            task.markCompleted(at: context.dayBoundary.now())
            context.store.notifyChanged()
            context.recurrence.scheduleNextOccurrence(after: task)
            // 유예 우회 경로라 연결 주간 목표 +1을 직접 보정한다 (§20.2).
            if let goalID = task.weeklyGoalID {
                context.store.incrementGoalCount(id: goalID)
            }
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

/// 주간 목표 진행 링(브리핑 전용 컴팩트) — 미니 요약·리뷰 행에서 진행률을 한눈에.
/// 사이드바 진행 링과 별개의 파일 로컬 구현(소유 경계 유지). progress는 0~1 캡된 값.
private struct BriefingGoalRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.divider, lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
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
