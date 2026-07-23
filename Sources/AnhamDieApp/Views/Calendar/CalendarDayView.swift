import SwiftUI

/// 일간 뷰 (PLAN §12.1): 그날 하나를 넓은 단일 리스트로 — 우측 날짜 패널의 전체폭 확장판.
/// 제목은 잘리지 않게 넉넉히 표시(§12.1 "제목 전체 표시"). 편집·체크·정렬은 MainTaskRow 재사용.
/// "이 날 할 일 추가"는 하단 별도 영역(§11.1).
struct CalendarDayView: View {
    let day: Date
    let store: TaskStore
    let boundary: DayBoundaryService

    @State private var expandedTaskID: UUID?

    /// 일간 뷰는 폭이 넓으므로 제목을 사실상 전체 표시한다 (§12.1).
    private let titleLineLimit = 6

    var body: some View {
        // 표시 정렬은 스토어 순서 API(store.tasks(on:))를 그대로 따른다 — 자체 재정렬 금지(§11.3).
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
                            .padding(.vertical, 12)
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
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 28)
                // §12.1: 제목 전체 표시 — 넓은 폭에서 필요한 만큼 줄바꿈.
                .environment(\.taskRowTitleLineLimit, titleLineLimit)
                // §12.6: 일간 뷰의 행 드롭은 수동 정렬만 — 날짜 간 이동(reschedule)은 '해야할 일' 리스트 전용(v3 동작).
                .environment(\.taskRowReorderOnly, true)
            }
            addSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.surface)
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(relativeLabel)
                    .font(AppTheme.rowMeta)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            if count > 0 {
                Text("\(count)개")
                    .font(AppTheme.badge)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AppTheme.divider.opacity(0.8), in: Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// 패널 최하단의 별도 입력 영역 (§11.1) — 목록과 구분선으로 분리해 항상 바닥에 고정.
    private var addSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListRowDivider()
            MainTokenAddRow(placeholder: "이 날 할 일 추가", onSubmit: addTask)
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
        }
        .background(AppTheme.surface)
    }

    private var relativeLabel: String {
        let today = boundary.logicalToday()
        if day == today { return "오늘" }
        if day == boundary.logicalYesterday() { return "어제" }
        if day == boundary.calendar.date(byAdding: .day, value: 1, to: today) { return "내일" }
        let diff = boundary.calendar.dateComponents([.day], from: today, to: day).day ?? 0
        return diff < 0 ? "\(-diff)일 전" : "\(diff)일 후"
    }

    // 날짜 토큰이 없으면 이 뷰의 날짜로 예정된다 (초기 배치·태그 생성은 MainInlineAdd 단일 경로).
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
