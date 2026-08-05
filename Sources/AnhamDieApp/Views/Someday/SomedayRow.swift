import SwiftUI
import UniformTypeIdentifiers

/// '언젠가' 리스트의 한 행 (PLAN §22.2). 체크(완료 유예)·제목(더블클릭 인라인 편집)·태그 칩·
/// 우선순위 막대·메모 미리보기(§17 환경값 준용)에 [오늘 하기] 토글을 얹는다.
/// [오늘 하기]는 store.pullToToday(§22.3: bucket=active·오늘·somedayOrigin), 이미 오늘이면
/// store.returnToSomeday로 되돌린다. 드래그는 taskDragItemProvider(공용)로 실려 '언젠가' 내부
/// 수동정렬(TaskReorderDropDelegate reorderOnly)과 '해야할 일' 리스트로의 드래그를 함께 태운다.
struct SomedayRow: View {
    let task: TodoTask
    let store: TaskStore
    let boundary: DayBoundaryService

    @State private var isHovering = false
    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @State private var dropEdge: DropEdge?
    @State private var rowHeight: CGFloat = 0
    @FocusState private var titleFieldFocused: Bool

    // §17: 메모 미리보기는 컨테이너 opt-in + 설정 켬일 때만.
    @Environment(\.taskRowShowsNotePreview) private var showsNotePreview

    private var settings: AppSettings { AppContext.shared.settings }
    // 완료 토글 단일 경로(§11.6) — 유예 시작/취소가 컨트롤러에서 처리된다.
    private var grace: CompletionGraceController { CompletionGraceController.shared }

    /// 이미 오늘로 꺼내진 '언젠가' 항목인지 (§22.3). someday 풀에 남아 있으면 false.
    private var isPulledToday: Bool { task.bucket != .someday }

    private var isPending: Bool { grace.isPending(task) }
    private var displayCompleted: Bool { task.isCompleted || isPending }

    /// §17 메모 미리보기 첫 줄 — 없으면 nil이라 행 높이 불변.
    private var notePreview: String? {
        guard showsNotePreview, settings.showNotePreview else { return nil }
        return NotePreview.firstLine(task.note)
    }

    var body: some View {
        HStack(spacing: AppTheme.rowSpacing) {
            MainCheckbox(isDone: displayCompleted, action: toggleDone)

            titleColumn

            Spacer(minLength: 6)

            RowTagPills(tags: store.tags(of: task))

            todayButton

            if isHovering {
                iconButton("trash", help: "삭제", tint: AppTheme.overdue) {
                    RowAction.delete(task, store: store)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, AppTheme.rowVerticalPadding)
        .frame(minHeight: AppTheme.rowMinHeight)
        .contentShape(Rectangle())
        .background(rowBackground)
        // v5(§13.4): 우선순위 = 리딩 엣지 세로 색 막대. 히트테스트 비활성 — 행 드래그/드롭은 그대로 전달.
        .overlay(alignment: .leading) {
            PriorityBar(priority: task.priority)
                .padding(.vertical, 6)
                .allowsHitTesting(false)
        }
        .overlay(TaskReorderIndicator(edge: dropEdge))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { rowHeight = $0 })
        // 드래그 소스(§11.3): '언젠가' 내부 수동정렬. '해야할 일' 리스트로의 드롭 처리는 스케줄 뷰 소관.
        .onDrag { taskDragItemProvider(task) }
        // reorderOnly=true — '언젠가' 리스트 안 드롭은 날짜 변경 없이 순서만 바꾼다.
        .onDrop(of: [.text], delegate: TaskReorderDropDelegate(
            target: task, store: store, rowHeight: rowHeight, reorderOnly: true, edge: $dropEdge
        ))
        .onHover { isHovering = $0 }
        .contextMenu { contextMenu }
        // 재정렬 스왑(§12.7): sortOrder 변화에만 반응해 미끄러지듯 이동.
        .reorderMotion(value: task.sortOrder)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius)
            .fill(isHovering ? AppTheme.hoverBackground : Color.clear)
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
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(task.title)
                    // 단일 클릭과 공존하도록 simultaneousGesture로 더블클릭만 편집에 쓴다.
                    .simultaneousGesture(TapGesture(count: 2).onEnded { beginEditingTitle() })
            }

            if let preview = notePreview {
                Text(preview)
                    .font(AppTheme.rowMeta)
                    .foregroundStyle(displayCompleted ? AppTheme.textDisabled : AppTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    // MARK: [오늘 하기] 토글 (§22.3)

    private var todayButton: some View {
        Button { toggleToday() } label: {
            HStack(spacing: 4) {
                Image(systemName: isPulledToday ? "checkmark.circle.fill" : "arrow.up.forward.circle")
                Text(isPulledToday ? "오늘 있음" : "오늘 하기")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(AppTheme.accent.opacity(isPulledToday ? 0.22 : 0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isPulledToday ? "오늘 목록에서 빼기(언젠가로 복귀)" : "오늘 할 일로 가져오기")
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button { beginEditingTitle() } label: {
            Label("이름 편집", systemImage: "pencil")
        }

        Divider()

        Button { toggleToday() } label: {
            Label(isPulledToday ? "오늘 목록에서 빼기" : "오늘 하기",
                  systemImage: isPulledToday ? "arrow.uturn.left" : "sun.max")
        }

        Menu {
            PriorityMenuContent(task: task, store: store)
        } label: {
            Label("우선순위", systemImage: "flag")
        }

        if !store.tags.isEmpty {
            Menu {
                TagMenuContent(task: task, store: store)
            } label: {
                Label("태그", systemImage: "tag")
            }
        }

        Divider()

        Button(role: .destructive) {
            RowAction.delete(task, store: store)
        } label: {
            Label("삭제", systemImage: "trash")
        }
    }

    // MARK: 액션

    private func toggleToday() {
        if isPulledToday {
            store.returnToSomeday(task)
        } else {
            store.pullToToday(task, boundary: boundary)
        }
    }

    // 완료 토글 단일 경로(§11.6) — task.markCompleted 직접 호출 금지.
    private func toggleDone() {
        withAnimation(.easeInOut(duration: 0.2)) {
            grace.toggleCompletion(of: task)
        }
    }

    private func beginEditingTitle() {
        draftTitle = task.title
        isEditingTitle = true
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

    private func iconButton(
        _ systemName: String,
        help: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
