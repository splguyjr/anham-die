import SwiftUI
import UniformTypeIdentifiers

/// 행 제목 최대 줄 수 (§11.1) — 기본 1줄(메인 리스트), 캘린더 날짜 패널이 2를 주입한다.
/// MainTaskRow 시그니처는 v2 계약으로 동결이라 Environment로만 확장한다.
private struct TaskRowTitleLineLimitKey: EnvironmentKey {
    static let defaultValue = 1
}

extension EnvironmentValues {
    var taskRowTitleLineLimit: Int {
        get { self[TaskRowTitleLineLimitKey.self] }
        set { self[TaskRowTitleLineLimitKey.self] = newValue }
    }
}

/// 행 드롭이 날짜 간 이동(reschedule)까지 하는지 (§12.6). 기본 false = '해야할 일' 리스트(reschedule 허용).
/// 캘린더 일간 뷰/패널이 true를 주입해 그 안의 행 드롭은 수동 정렬만 하게 한다(v3 회귀 방지).
private struct TaskRowReorderOnlyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var taskRowReorderOnly: Bool {
        get { self[TaskRowReorderOnlyKey.self] }
        set { self[TaskRowReorderOnlyKey.self] = newValue }
    }
}

/// 제목 아래 메모 미리보기 한 줄을 그릴지 (§17). 기본 false — 메인 리스트 컨테이너(해야할 일/백로그/완료)만 true를 주입한다.
/// 캘린더 날짜 패널/일간 뷰·오버레이는 주입하지 않아 자연히 꺼진다(밀도 유지). 설정 토글이 꺼지면 주입 여부와 무관하게 숨는다.
private struct TaskRowShowsNotePreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var taskRowShowsNotePreview: Bool {
        get { self[TaskRowShowsNotePreviewKey.self] }
        set { self[TaskRowShowsNotePreviewKey.self] = newValue }
    }
}

/// 리스트 한 행 (PLAN §3.1 + §10.6): 체크박스 · 제목 · 우선순위/태그 색 점 · D-day/이월 배지.
/// 사용성(§10.6): 호버 인라인 액션, 우클릭 컨텍스트 메뉴, 더블클릭 제목 인라인 편집,
/// 행 선택(클릭/포커스)+키보드(⌫ 삭제·⌘1/2/3 우선순위·⌘T 오늘·⌘D 내일·Enter 상세).
/// 호출 시그니처는 v2 계약 — 리스트 뷰들이 그대로 쓰므로 변경 금지.
struct MainTaskRow: View {
    let task: TodoTask
    let store: TaskStore
    let boundary: DayBoundaryService
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    @State private var isHovering = false
    @State private var showDatePopover = false
    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    /// 드래그 정렬(§11.3): 드롭 삽입 위치 표시 + 대상 행 높이(위/아래 절반 판정용)
    @State private var dropEdge: DropEdge?
    @State private var headerHeight: CGFloat = 0
    @FocusState private var isRowFocused: Bool
    @FocusState private var titleFieldFocused: Bool
    @Environment(\.taskRowTitleLineLimit) private var titleLineLimit
    /// §12.6: 캘린더 일간 뷰/패널에서는 true — 행 드롭이 날짜 변경 없이 수동 정렬만 하도록 델리게이트에 전달.
    @Environment(\.taskRowReorderOnly) private var reorderOnly
    /// §17: 메인 리스트 컨테이너에서만 true — 제목 아래 메모 첫 줄 미리보기 opt-in. 설정 토글과 AND.
    @Environment(\.taskRowShowsNotePreview) private var showsNotePreview

    private var settings: AppSettings { AppContext.shared.settings }

    /// §17 메모 미리보기 첫 줄 — 컨테이너 opt-in + 설정 켬 + 메모에 내용이 있을 때만. 없으면 nil이라 행 높이가 불변.
    private var notePreview: String? {
        guard showsNotePreview, settings.showNotePreview else { return nil }
        return NotePreview.firstLine(task.note)
    }

    /// 완료 유예 컨트롤러 (§11.6) — 체크 토글 단일 경로. pendingTaskIDs 관찰로 유예 중 표시가 갱신된다.
    private var grace: CompletionGraceController { CompletionGraceController.shared }
    /// 유예 중(체크됐지만 미확정) 여부
    private var isPending: Bool { grace.isPending(task) }
    /// 완료로 그릴지 — 실제 완료 또는 유예 중(체크됨+취소선, 목록에서 제거하지 않음 §11.6)
    private var displayCompleted: Bool { task.isCompleted || isPending }

    private var subtaskProgress: String? {
        guard !task.subtasks.isEmpty else { return nil }
        let done = task.subtasks.filter { $0.isDone }.count
        return "\(done)/\(task.subtasks.count)"
    }

    /// 호버·포커스·날짜 팝오버 중 하나라도 활성이면 인라인 액션을 노출한다.
    /// (액션 클러스터는 항상 배치하고 가시성만 토글해 팝오버·메뉴 앵커를 안정적으로 유지한다.)
    private var showActions: Bool { isHovering || isRowFocused || showDatePopover }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                MainTaskDetailView(task: task, store: store, boundary: boundary)
                    .padding(.leading, 28)
                    .padding(.trailing, 2)
                    .padding(.bottom, 10)
            }
        }
        // 재정렬 스왑(§12.7): sortOrder 변화에만 반응해 새 위치로 미끄러지듯 이동(점프 제거).
        // 드롭 순서 조정(§11.3)·완료 유예(§11.6)·호버/편집은 sortOrder를 바꾸지 않으므로 영향받지 않는다.
        .reorderMotion(value: task.sortOrder)
    }

    private var header: some View {
        HStack(spacing: AppTheme.rowSpacing) {
            MainCheckbox(isDone: displayCompleted, action: toggleDone)

            titleColumn

            Spacer(minLength: 6)

            // v5(§13.4): 태그 = 글자 칩(TagPill) 트레일링 나열, 넘치면 "+N". 색점 방식 제거.
            RowTagPills(tags: store.tags(of: task))

            if task.isRecurring {
                MainRecurrenceBadge(rule: task.recurrence)
            }
            if task.rolloverCount > 0 {
                MainRolloverBadge(count: task.rolloverCount)
            }
            if let due = task.dueDate {
                MainDDayBadge(dDay: boundary.dDay(of: due))
            }
            // §20.2·§20.4 ③: 주간 목표 연결 task는 트레일링에 ↗주간 배지(클릭 시 목표명·진행).
            if let goalID = task.weeklyGoalID {
                WeeklyGoalBadge(goalID: goalID, store: store)
            }

            RowHoverActions(
                task: task,
                store: store,
                boundary: boundary,
                showDatePopover: $showDatePopover
            )
            .opacity(showActions ? 1 : 0)
            .allowsHitTesting(showActions)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, AppTheme.rowVerticalPadding)
        .frame(minHeight: AppTheme.rowMinHeight)
        .contentShape(Rectangle())
        .background(rowBackground)
        // v5(§13.4): 우선순위 = 행 리딩 엣지의 세로 색 막대(PriorityBar). 색점 방식 제거.
        // 히트테스트 비활성 — 행 탭/드래그/드롭은 그대로 아래로 전달된다.
        .overlay(alignment: .leading) {
            PriorityBar(priority: task.priority)
                .padding(.vertical, 6)
                .allowsHitTesting(false)
        }
        .overlay(TaskReorderIndicator(edge: dropEdge))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { headerHeight = $0 })
        // 드래그 정렬(§11.3): 헤더를 드래그 소스로, 대상 행의 앞/뒤로 삽입. 창/창 밖 이동과 무관하게 순서만 바꾼다.
        .onDrag { taskDragItemProvider(task) }
        .onDrop(
            of: [.text],
            delegate: TaskReorderDropDelegate(
                target: task, store: store, rowHeight: headerHeight,
                reorderOnly: reorderOnly, edge: $dropEdge
            )
        )
        .onHover { isHovering = $0 }
        .focusable()
        .focused($isRowFocused)
        .focusEffectDisabled()
        .onTapGesture { if !isEditingTitle { isRowFocused = true } }
        .onKeyPress(action: handleKeyPress)
        .contextMenu {
            TaskRowContextMenu(
                task: task,
                store: store,
                boundary: boundary,
                onPickDate: { showDatePopover = true },
                onRename: beginEditingTitle,
                onToggleExpand: onToggleExpand
            )
        }
        .popover(isPresented: $showDatePopover, arrowEdge: .bottom) {
            // §21.10: 이 바인딩의 set(nil)은 백로그 이동(moveToBacklog)이라 그에 맞는 라벨·아이콘·툴팁을 준다.
            DueDateControls(
                date: scheduledDateBinding,
                boundary: boundary,
                settings: settings,
                clearLabel: "날짜 비우기 · 백로그",
                clearSystemImage: "tray",
                clearHelp: "일정을 비우고 백로그로 이동합니다"
            )
            .padding(12)
            .frame(minWidth: 240)
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius)
            .fill(isRowFocused ? AppTheme.selectedBackground
                  : (isHovering ? AppTheme.hoverBackground : Color.clear))
    }

    @ViewBuilder
    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isEditingTitle {
                TextField("제목", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(AppTheme.rowTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                    .focused($titleFieldFocused)
                    .onSubmit(commitTitle)
                    .onExitCommand(perform: cancelEditingTitle)
                    .onChange(of: titleFieldFocused) { _, focused in
                        if !focused { commitTitle() }
                    }
            } else {
                Text(task.title)
                    .font(AppTheme.rowTitle)
                    .foregroundStyle(displayCompleted ? AppTheme.textDisabled : AppTheme.textPrimary)
                    .strikethrough(displayCompleted, color: AppTheme.textDisabled)
                    .lineLimit(titleLineLimit)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(task.title)
                    // 단일 클릭(행 선택)과 공존하도록 simultaneousGesture로 더블클릭만 편집에 쓴다.
                    .simultaneousGesture(TapGesture(count: 2).onEnded { beginEditingTitle() })
            }

            // §17: 메모 첫 줄 미리보기 — 보조 텍스트 한 줄(rowMeta·textSecondary). 메모 없으면 아예 그리지 않아 높이 불변.
            // 완료/유예 중엔 제목처럼 textDisabled로 죽인다(취소선은 제목 전용 — 진행률 줄과 동일 규칙).
            if let preview = notePreview {
                Text(preview)
                    .font(AppTheme.rowMeta)
                    .foregroundStyle(displayCompleted ? AppTheme.textDisabled : AppTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let progress = subtaskProgress {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 9))
                    Text(progress)
                        .font(AppTheme.rowMeta)
                }
                .foregroundStyle(AppTheme.textDisabled)
            }
        }
    }

    // MARK: - 날짜 바인딩 (호버/컨텍스트 날짜 팝오버용 — 행이 속한 날짜 = scheduledDate)

    private var scheduledDateBinding: Binding<Date?> {
        Binding(
            get: { task.scheduledDate },
            // §13.3 백로그 불변식: 팝오버 '지우기'(nil)는 백로그 진입의 네 번째 경로다.
            // scheduledDate만 nil로 두면 rolloverCount가 남아 백로그에 ↺ 배지가 샌다.
            // RolloverService·우클릭·상세 뷰와 동일하게 RowAction.moveToBacklog로 위임해 봉인한다.
            set: {
                if let date = $0 {
                    task.scheduledDate = date
                    store.notifyChanged()
                } else {
                    RowAction.moveToBacklog(task, store: store)
                }
            }
        )
    }

    // MARK: - 인라인 제목 편집

    private func beginEditingTitle() {
        draftTitle = task.title
        isEditingTitle = true
        // TextField 등장 직후 포커스를 준다.
        DispatchQueue.main.async { titleFieldFocused = true }
    }

    private func commitTitle() {
        guard isEditingTitle else { return }
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != task.title {
            task.title = trimmed
            store.notifyChanged()
        }
        isEditingTitle = false
    }

    private func cancelEditingTitle() {
        isEditingTitle = false
    }

    // MARK: - 키보드 (행 선택 상태)

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard !isEditingTitle else { return .ignored }
        let mods = press.modifiers
        let hasModifier = mods.contains(.command) || mods.contains(.option) || mods.contains(.control)

        if !hasModifier {
            switch press.key.character {
            case "\u{7F}": // Backspace/Delete
                RowAction.delete(task, store: store)
                return .handled
            case "\r": // Return → 상세 토글
                onToggleExpand()
                return .handled
            default:
                break
            }
        }

        if mods.contains(.command) {
            switch press.characters.lowercased() {
            case "1": RowAction.setPriority(task, .high, store: store); return .handled
            case "2": RowAction.setPriority(task, .normal, store: store); return .handled
            case "3": RowAction.setPriority(task, .low, store: store); return .handled
            case "t": RowAction.moveToToday(task, store: store, boundary: boundary); return .handled
            case "d": RowAction.moveToTomorrow(task, store: store, boundary: boundary); return .handled
            default: break
            }
        }
        return .ignored
    }

    // 완료 토글 단일 경로(§11.6): 유예 시작/취소·완료 해제·반복 다음 발생 생성이 컨트롤러에서 처리된다.
    // (task.markCompleted 직접 호출 금지 — 유예·반복이 여기서 일어난다.)
    private func toggleDone() {
        withAnimation(.easeInOut(duration: 0.2)) {
            grace.toggleCompletion(of: task)
        }
    }
}

/// v5 태그 나열 (PLAN §13.4) — 행 트레일링에 TagPill을 나열하고, maxVisible을 넘으면 "+N"으로 접는다.
/// 리스트 계열(메인·오버레이·캘린더 일간/패널)이 공유한다. 색점 방식을 대체한다.
struct RowTagPills: View {
    let tags: [Tag]
    var maxVisible: Int = 3

    var body: some View {
        if !tags.isEmpty {
            let visible = Array(tags.prefix(maxVisible))
            let overflow = tags.count - visible.count
            HStack(spacing: 4) {
                ForEach(visible) { tag in
                    TagPill(tag)
                }
                if overflow > 0 {
                    Text("+\(overflow)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        // 캡슐 채움에 divider 금지(하이콘트라스트 3.6:1 미달) — 글자색 12% 틴트 관례.
                        .background(AppTheme.textSecondary.opacity(0.12), in: Capsule())
                        .help("태그 \(tags.count)개 중 \(overflow)개 더")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// ↗주간 배지 (PLAN §20.2·§20.4 ③) — weeklyGoalID로 주간 목표에 연결된 task 행의 트레일링 표식.
/// 클릭하면 목표명·진행을 팝오버로 보여준다(호버 .help 툴팁 병행). 배지 추가만 — 행 기존 상호작용은 불변.
struct WeeklyGoalBadge: View {
    let goalID: UUID
    let store: TaskStore

    @State private var showInfo = false

    private var goal: WeeklyGoal? { store.weeklyGoal(withID: goalID) }

    var body: some View {
        Button {
            showInfo.toggle()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .bold))
                Text("주간")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(MainTheme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(MainTheme.accent.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .popover(isPresented: $showInfo, arrowEdge: .bottom) {
            popover
                .padding(12)
                .frame(minWidth: 180)
        }
    }

    private var tooltip: String {
        guard let goal else { return "주간 목표" }
        return "\(goal.title) · \(goal.currentCount)/\(goal.targetCount)"
    }

    @ViewBuilder
    private var popover: some View {
        if let goal {
            VStack(alignment: .leading, spacing: 8) {
                Text(goal.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                HStack(spacing: 8) {
                    ProgressView(value: goal.progress)
                        .frame(width: 120)
                    Text("\(goal.currentCount)/\(goal.targetCount)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                if goal.isAchieved {
                    Label("달성", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MainTheme.accent)
                } else if goal.isRoutine {
                    Text("루틴 · 잔여 \(goal.remainingCount)회")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        } else {
            Text("연결된 주간 목표를 찾을 수 없습니다")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}
