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

    private var settings: AppSettings { AppContext.shared.settings }

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

            HStack(spacing: 5) {
                if task.priority != .normal {
                    MainColorDot(color: AppTheme.priorityColor(task.priority))
                }
                ForEach(store.tags(of: task)) { tag in
                    MainColorDot(color: AppTheme.tagColor(tag.colorHex))
                }
            }

            if task.isRecurring {
                MainRecurrenceBadge(rule: task.recurrence)
            }
            if task.rolloverCount > 0 {
                MainRolloverBadge(count: task.rolloverCount)
            }
            if let due = task.dueDate {
                MainDDayBadge(dDay: boundary.dDay(of: due))
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
        .overlay(TaskReorderIndicator(edge: dropEdge))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { headerHeight = $0 })
        // 드래그 정렬(§11.3): 헤더를 드래그 소스로, 대상 행의 앞/뒤로 삽입. 창/창 밖 이동과 무관하게 순서만 바꾼다.
        .onDrag { taskDragItemProvider(task) }
        .onDrop(
            of: [.text],
            delegate: TaskReorderDropDelegate(
                target: task, store: store, rowHeight: headerHeight, edge: $dropEdge
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
            DueDateControls(date: scheduledDateBinding, boundary: boundary, settings: settings)
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
            set: { task.scheduledDate = $0; store.notifyChanged() }
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
