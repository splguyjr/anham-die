import SwiftUI

/// 날짜 클릭 시 우측에 뜨는 그 날 목록 패널 (PLAN §10.2): 체크·편집 가능한 MainTaskRow 재사용 + 인라인 추가.
struct CalendarDayPanel: View {
    let day: Date
    let store: TaskStore
    let boundary: DayBoundaryService
    let onClose: () -> Void

    @State private var expandedTaskID: UUID?

    var body: some View {
        // 표시 정렬은 스토어의 순서 API(store.tasks(on:) → displayOrder)를 그대로 따른다 — 자체 재정렬 금지(§11.3).
        let tasks = store.tasks(on: day, boundary: boundary)
        VStack(alignment: .leading, spacing: 0) {
            header(count: tasks.count)
            ListRowDivider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if tasks.isEmpty {
                        Text("이 날 할 일이 없습니다")
                            .font(AppTheme.rowMeta)
                            .foregroundStyle(AppTheme.textDisabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    }
                    ForEach(tasks) { task in
                        MainTaskRow(
                            task: task,
                            store: store,
                            boundary: boundary,
                            isExpanded: expandedTaskID == task.id,
                            onToggleExpand: { toggleExpand(task.id) }
                        )
                        ListRowDivider()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
                // §11.1: 패널 폭이 좁아 행 제목은 최대 2줄까지 줄바꿈 (메인 리스트는 기본 1줄 유지).
                .environment(\.taskRowTitleLineLimit, 2)
            }
            // §11.1: "이 날 할 일 추가"를 목록과 분리해 패널 최하단 구분선 아래 별도 영역으로 둔다.
            addSection
        }
        // 폭은 부모(CalendarView)가 calendarPanelWidth로 지정한다 (§12.2 드래그 조절).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surfaceSecondary)
    }

    /// 패널 최하단의 별도 입력 영역 (§11.1) — 목록과 구분선으로 분리해 항상 바닥에 고정된다.
    private var addSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListRowDivider()
            // §11.8: 해야할 일·백로그 인라인 추가와 토큰 문법(#태그 !우선순위 날짜)을 통일한다.
            MainTokenAddRow(placeholder: "이 날 할 일 추가", onSubmit: addTask)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
        }
        .background(AppTheme.surfaceSecondary)
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CalendarFormatters.dayPanelTitle.string(from: day))
                    .font(AppTheme.sectionTitle)
                    .foregroundStyle(titleColor)
                    // §11.1: 제목 잘림 제거 — 폭에 맞춰 최대 2줄, 그래도 넘치면 말줄임 + 툴팁.
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(CalendarFormatters.dayPanelTitle.string(from: day))
                Text(relativeLabel)
                    .font(AppTheme.rowMeta)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(AppTheme.badge)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppTheme.divider.opacity(0.8), in: Capsule())
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textDisabled)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var titleColor: Color {
        day == boundary.logicalToday() ? AppTheme.accent : AppTheme.textPrimary
    }

    private var relativeLabel: String {
        let today = boundary.logicalToday()
        if day == today { return "오늘" }
        if day == boundary.logicalYesterday() { return "어제" }
        if day == boundary.calendar.date(byAdding: .day, value: 1, to: today) { return "내일" }
        let diff = boundary.calendar.dateComponents([.day], from: today, to: day).day ?? 0
        return diff < 0 ? "\(-diff)일 전" : "\(diff)일 후"
    }

    // 날짜 토큰이 없으면 이 패널의 날짜로 예정된다 (초기 배치·태그 생성은 MainInlineAdd 단일 경로).
    private func addTask(_ parse: QuickAddParse) {
        MainInlineAdd.commit(
            parse,
            defaultScheduled: boundary.scheduledDateValue(for: day),
            extraTag: nil,
            store: store,
            boundary: boundary,
            settings: AppContext.shared.settings
        )
    }

    private func toggleExpand(_ id: UUID) {
        expandedTaskID = (expandedTaskID == id) ? nil : id
    }
}
