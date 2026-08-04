import SwiftUI
import UniformTypeIdentifiers

/// "해야할 일" 뷰 v4 (PLAN §12.4~§12.7): 섹션을 ① 지난 할 일 · ② 오늘 · ③ 예정 3개로 축소.
/// ③ 예정은 내일 이후 전체를 하나의 연속 리스트로 렌더하고, 각 날짜 그룹 첫 항목에만
/// 인라인 미니 날짜 구분선("내일 7/24"/"7/28 (월)")을 그린다(섹션 헤더 아님).
/// 소속 판정·정렬은 store.todoSectionsV4(§12.4 = scheduleSections 위임)가 단일 소스 — 여기선 표시만 한다.
/// 날짜 간 드래그(§12.6): 오늘 헤더/미니 구분선을 드롭 타깃으로 삼아 ScheduleDrag로 scheduledDate 변경,
/// 같은 그룹 내 행-행 드래그(수동 정렬)는 MainTaskRow 내부 TaskReorderDropDelegate가 그대로 처리한다.
/// 행 내부(체크·배지·호버 액션·완료 유예 §11)는 MainTaskRow(row-ux 모듈) 소관 — 호출만 한다.
struct ScheduleListView: View {
    var tagFilter: Tag? = nil

    @State private var expandedTaskID: UUID?

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }
    private var settings: AppSettings { AppContext.shared.settings }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d (E)"
        return f
    }()

    var body: some View {
        // 관찰: 논리적 하루 경계 통과 시 TriggerService가 갱신 → 섹션이 새 '오늘' 기준으로 재평가된다.
        let _ = AppContext.shared.settings.currentLogicalDay
        let sections = store.todoSectionsV4(boundary: boundary, tagFilter: tagFilter)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // §20.4 ②: '해야할 일' 상단 이번 주 목표 요약 스트립. 태그 필터 뷰에는 표시 안 함.
                if tagFilter == nil {
                    WeeklyGoalSummaryCard()
                }
                if !sections.past.isEmpty {
                    pastSection(sections.past)
                }
                todaySection(sections.today)
                upcomingSection(sections.upcoming)
            }
            .padding(.horizontal, AppTheme.contentPadding)
            .padding(.bottom, 24)
            // §12.7 재정렬 모션: 표시 순서(id 시퀀스)가 바뀔 때만 부드러운 스왑 애니메이션.
            // 호버/포커스 등 다른 상태 변화는 순서 시그니처가 그대로라 애니메이션되지 않는다.
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: orderSignature(sections))
        }
        .background(AppTheme.surface)
        // §17: 메인 리스트 계열에서만 메모 미리보기 opt-in (캘린더/오버레이는 미주입 → 꺼짐).
        .environment(\.taskRowShowsNotePreview, true)
        .navigationTitle(tagFilter.map { "#\($0.name)" } ?? "해야할 일")
    }

    // MARK: - ① 지난 할 일 (past 비면 body에서 섹션 자체를 생략)

    @ViewBuilder
    private func pastSection(_ tasks: [TodoTask]) -> some View {
        ListSectionHeader(title: "🔴 지난 할 일", count: tasks.count, titleColor: AppTheme.overdue)
        rows(ordered(tasks))
    }

    // MARK: - ② 오늘 (헤더가 reschedule 드롭 타깃 · 인라인 추가행 기본=오늘)

    @ViewBuilder
    private func todaySection(_ tasks: [TodoTask]) -> some View {
        let today = boundary.logicalToday()
        RescheduleDropZone(group: .today, tagFilter: tagFilter) { targeted in
            ListSectionHeader(
                title: "오늘 \(Self.dayFormatter.string(from: today))",
                count: tasks.count,
                titleColor: AppTheme.accent
            )
            .background(rescheduleHighlight(targeted))
        }

        // 인라인 추가는 오늘 섹션 상단 — 날짜 토큰 없으면 오늘에 배정(§11.8).
        MainTokenAddRow(placeholder: addPlaceholder(suffix: "오늘 할 일"), onSubmit: addToday)
        ListRowDivider()

        rows(ordered(tasks))
    }

    // MARK: - ③ 예정 (내일 이후 연속 리스트 + 인라인 미니 구분선 · 추가행 기본=내일)

    @ViewBuilder
    private func upcomingSection(_ items: [UpcomingItem]) -> some View {
        ListSectionHeader(title: "예정", count: items.count, titleColor: AppTheme.textPrimary)

        // §12.5 미래 추가행: 기본 날짜=내일, 날짜 토큰으로 임의 날짜 지정.
        MainTokenAddRow(placeholder: addPlaceholder(suffix: "예정 할 일 (기본 내일)"), onSubmit: addUpcoming)
        ListRowDivider()

        if items.isEmpty {
            emptyRow
        } else {
            // 단일 ForEach: item.isGroupStart일 때만 미니 구분선(dividerLabel)을 앞에 그린다(§12.4).
            ForEach(items) { item in
                if item.isGroupStart {
                    UpcomingMiniDivider(
                        label: item.dividerLabel ?? "",
                        day: item.day,
                        tagFilter: tagFilter
                    )
                }
                MainTaskRow(
                    task: item.task,
                    store: store,
                    boundary: boundary,
                    isExpanded: expandedTaskID == item.task.id,
                    onToggleExpand: { toggleExpand(item.task.id) }
                )
                ListRowDivider()
            }
        }
    }

    // MARK: - 공용 행 렌더

    @ViewBuilder
    private func rows(_ tasks: [TodoTask]) -> some View {
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

    private var emptyRow: some View {
        Text("예정된 할 일 없음")
            .font(AppTheme.rowMeta)
            .foregroundStyle(AppTheme.textDisabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppTheme.rowVerticalPadding)
    }

    private func addPlaceholder(suffix: String) -> String {
        tagFilter.map { "#\($0.name)에 \(suffix) 추가" } ?? "\(suffix) 추가"
    }

    private func rescheduleHighlight(_ targeted: Bool) -> some View {
        RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius)
            .fill(targeted ? AppTheme.accent.opacity(0.12) : Color.clear)
    }

    // 완료 항목은 하단으로 내려 취소선 표시(§7) — 상대 순서 유지(안정 정렬).
    private func ordered(_ tasks: [TodoTask]) -> [TodoTask] {
        tasks.filter { !$0.isCompleted } + tasks.filter { $0.isCompleted }
    }

    /// §12.7 애니메이션 트리거용 표시 순서 시그니처: 지난 → 오늘 → 예정 순 id 시퀀스.
    private func orderSignature(_ s: TodoSectionsV4) -> [UUID] {
        ordered(s.past).map(\.id) + ordered(s.today).map(\.id) + s.upcoming.map(\.task.id)
    }

    // MARK: - 추가 (오늘 / 예정)

    // 날짜 토큰 없으면 오늘. 태그 필터 뷰에선 그 태그도 부여.
    private func addToday(_ parse: QuickAddParse) {
        MainInlineAdd.commit(
            parse,
            defaultScheduled: boundary.scheduledToday(),
            extraTag: tagFilter,
            store: store,
            boundary: boundary,
            settings: settings
        )
    }

    // §12.5 날짜 토큰 없으면 내일(내일 이후 추가 허용), 있으면 그 날짜. 태그 필터 뷰에선 그 태그도 부여.
    private func addUpcoming(_ parse: QuickAddParse) {
        let tomorrow = boundary.calendar.date(byAdding: .day, value: 1, to: boundary.logicalToday())!
        MainInlineAdd.commit(
            parse,
            defaultScheduled: boundary.scheduledDateValue(for: tomorrow),
            extraTag: tagFilter,
            store: store,
            boundary: boundary,
            settings: settings
        )
    }

    private func toggleExpand(_ id: UUID) {
        expandedTaskID = (expandedTaskID == id) ? nil : id
    }
}

// MARK: - 예정 인라인 미니 구분선 (섹션 헤더 아님) + 날짜 reschedule 드롭 타깃 (§12.4·§12.6)

/// 작은 라벨 + 얇은 선. 이 날짜로 다른 그룹 태스크를 드롭하면 scheduledDate가 이 날짜로 변경된다.
private struct UpcomingMiniDivider: View {
    let label: String
    let day: Date
    let tagFilter: Tag?

    var body: some View {
        RescheduleDropZone(group: .upcoming(day), tagFilter: tagFilter) { targeted in
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(targeted ? AppTheme.accent : AppTheme.textSecondary)
                Rectangle()
                    .fill(targeted ? AppTheme.accent : AppTheme.divider.opacity(0.7))
                    .frame(height: 1)
            }
            .padding(.top, 14)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - reschedule 드롭 존 (§12.6)

/// 드롭 타깃 래퍼. content(isTargeted)로 강조 상태를 넘겨준다.
/// 같은 그룹 드롭은 ScheduleDrag가 reorder(무동작)로 판정하므로 순서 조정은 행-행 드래그가 담당한다.
private struct RescheduleDropZone<Content: View>: View {
    let group: ScheduleGroup
    let tagFilter: Tag?
    @ViewBuilder let content: (Bool) -> Content

    @State private var isTargeted = false

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }

    var body: some View {
        content(isTargeted)
            .onDrop(
                of: [.text],
                delegate: ScheduleRescheduleDropDelegate(
                    targetGroup: group,
                    store: store,
                    boundary: boundary,
                    tagFilter: tagFilter,
                    isTargeted: $isTargeted
                )
            )
    }
}

/// 날짜 그룹 헤더/구분선에 대한 드롭 델리게이트. 드롭된 태스크의 소스 그룹을 스토어에서 조회한 뒤
/// ScheduleDrag.apply로 위임한다(다른 날짜 그룹=reschedule, 같은 그룹/past=무동작).
private struct ScheduleRescheduleDropDelegate: DropDelegate {
    let targetGroup: ScheduleGroup
    let store: TaskStore
    let boundary: DayBoundaryService
    let tagFilter: Tag?
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        let group = targetGroup
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String, let id = UUID(uuidString: string) else { return }
            Task { @MainActor in
                guard let task = store.task(withID: id),
                      let source = store.scheduleGroup(of: task, boundary: boundary, tagFilter: tagFilter)
                else { return }
                ScheduleDrag.apply(
                    dragged: task,
                    from: source,
                    to: group,
                    store: store,
                    boundary: boundary
                )
            }
        }
        return true
    }
}
