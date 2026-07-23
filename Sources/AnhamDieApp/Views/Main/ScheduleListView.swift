import SwiftUI

/// "해야할 일" 기본 뷰 (PLAN §10.1): 지난 할 일 → 오늘 → 내일 → 이후 날짜 섹션을 한 화면 스크롤.
/// 태그 필터 지정 시 해당 태그 태스크만 (사이드바 태그 선택).
/// 섹션 멤버십·정렬은 store.scheduleSections()가 단일 소스 — 여기선 표시만 한다.
/// 행 내부(체크·배지·호버 액션 §10.6)는 MainTaskRow(row-ux 모듈) 소관 — 호출만 한다.
struct ScheduleListView: View {
    var tagFilter: Tag? = nil

    @State private var expandedTaskID: UUID?

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d (E)"
        return f
    }()

    var body: some View {
        // 관찰: 논리적 하루 경계 통과 시 TriggerService가 갱신 → 섹션이 새 '오늘' 기준으로 재평가된다.
        let _ = AppContext.shared.settings.currentLogicalDay
        let today = boundary.logicalToday()
        let sections = store.scheduleSections(boundary: boundary, tagFilter: tagFilter)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    sectionView(section, isToday: section.day == today)
                }
            }
            .padding(.horizontal, AppTheme.contentPadding)
            .padding(.bottom, 24)
        }
        .background(AppTheme.surface)
        .navigationTitle(tagFilter.map { "#\($0.name)" } ?? "해야할 일")
    }

    // 섹션 = 헤더 + (오늘이면 인라인 추가 행) + 태스크 행들.
    @ViewBuilder
    private func sectionView(_ section: (day: Date?, tasks: [TodoTask]), isToday: Bool) -> some View {
        ListSectionHeader(
            title: sectionTitle(section.day),
            count: section.tasks.count,
            titleColor: sectionColor(section.day)
        )

        // 인라인 추가는 '오늘' 섹션 상단에 둔다 (PLAN §10.1) — 추가 시 기본 scheduledDate가 오늘이므로.
        if isToday {
            ListAddRow(placeholder: addPlaceholder, onSubmit: addTask)
            ListRowDivider()
        }

        if section.tasks.isEmpty {
            if !isToday {
                emptyRow
            }
        } else {
            ForEach(ordered(section.tasks)) { task in
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
    }

    private var emptyRow: some View {
        Text("예정된 할 일 없음")
            .font(AppTheme.rowMeta)
            .foregroundStyle(AppTheme.textDisabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppTheme.rowVerticalPadding)
    }

    private var addPlaceholder: String {
        tagFilter.map { "#\($0.name)에 오늘 할 일 추가" } ?? "오늘 할 일 추가"
    }

    // 완료 항목은 섹션 하단으로 내려 취소선으로 표시한다 (PLAN §7) — 상대 순서는 유지(안정 정렬).
    private func ordered(_ tasks: [TodoTask]) -> [TodoTask] {
        tasks.filter { !$0.isCompleted } + tasks.filter { $0.isCompleted }
    }

    private func sectionTitle(_ day: Date?) -> String {
        guard let day else { return "🔴 지난 할 일" }
        let base = Self.dayFormatter.string(from: day)
        let today = boundary.logicalToday()
        if day == today { return "오늘 \(base)" }
        if day == boundary.calendar.date(byAdding: .day, value: 1, to: today) {
            return "내일 \(base)"
        }
        return base
    }

    private func sectionColor(_ day: Date?) -> Color {
        guard let day else { return AppTheme.overdue }
        return day == boundary.logicalToday() ? AppTheme.accent : AppTheme.textPrimary
    }

    private func addTask(_ title: String) {
        let task = TodoTask(title: title)
        task.scheduledDate = boundary.scheduledToday()
        if let tag = tagFilter {
            task.tagIDs = [tag.id]
        }
        // 초기 배치는 스토어 단일 규칙(§11.3: 우선순위 → createdAt)으로 부여된다.
        store.addTaskApplyingInitialOrder(task)
    }

    private func toggleExpand(_ id: UUID) {
        expandedTaskID = (expandedTaskID == id) ? nil : id
    }
}
