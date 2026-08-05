import SwiftUI

/// 사이드바 '포스트잇' 뷰 (v10 §19.2) — 완료 히스토리 철학과 동일한 구조.
/// 상단: 열린 노트 목록(색 점 + 첫 줄 미리보기, 클릭 시 해당 카드 창 포커스).
/// 아래: 보관된 노트를 닫은 날짜별로 그룹(완료 히스토리 스타일) — 다시 열기 / 완전 삭제(확인).
/// 데이터 원천은 StickyStore(openNotes/archivedNotes) — @Observable이라 노트 변경 시 자동 재평가된다.
struct StickiesListView: View {
    /// 완전 삭제 확인 대상 (nil = 확인 없음).
    @State private var pendingDelete: StickyNote?
    /// 다중 선택 모드 여부 (§21.7) — 켜지면 보관 노트 행에 체크박스가 뜨고 탭이 선택 토글이 된다.
    @State private var selectionMode = false
    /// 선택된 보관 노트 id 집합 (§21.7).
    @State private var selection: Set<UUID> = []
    /// 다중 삭제 확인 표시 여부 (§21.7).
    @State private var showBulkDeleteConfirm = false

    private var stickies: StickyStore { AppContext.shared.stickies }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E)"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "a h:mm"
        return f
    }()

    var body: some View {
        // 관찰: 논리적 하루 경계 통과 시 '오늘'/'어제' 라벨이 새 기준으로 재평가된다.
        let _ = AppContext.shared.settings.currentLogicalDay
        let open = stickies.openNotes
        let groups = archivedGroups()
        ScrollView {
            LazyVStack(spacing: 0) {
                StickyNewNoteButton()
                ListRowDivider()

                ListSectionHeader(title: "열린 노트", count: open.count)
                if open.isEmpty {
                    ListEmptyState(message: "열린 포스트잇이 없습니다", systemImage: "note.text")
                }
                ForEach(open) { note in
                    StickyOpenRow(
                        note: note,
                        preview: previewLine(note),
                        isEmptyNote: isEmptyNote(note),
                        onFocus: { StickyNotesController.shared.open(note: note) },
                        onArchive: { StickyNotesController.shared.archive(note: note) }
                    )
                    ListRowDivider()
                }

                if !groups.isEmpty {
                    StickySelectionBar(
                        selectionMode: selectionMode,
                        selectedCount: selection.count,
                        onToggleMode: toggleSelectionMode,
                        onSelectAll: { selectAll(in: groups) },
                        onDeleteSelected: { showBulkDeleteConfirm = true }
                    )
                    ListRowDivider()
                }

                ForEach(groups, id: \.key) { group in
                    ListSectionHeader(title: group.label, count: group.notes.count)
                    ForEach(group.notes) { note in
                        StickyArchivedRow(
                            note: note,
                            preview: previewLine(note),
                            isEmptyNote: isEmptyNote(note),
                            time: Self.timeFormatter.string(from: note.archivedAt ?? note.createdAt),
                            selectionMode: selectionMode,
                            isSelected: selection.contains(note.id),
                            onToggleSelect: { toggleSelection(note.id) },
                            onReopen: { StickyNotesController.shared.open(note: note) },
                            onDelete: { pendingDelete = note }
                        )
                        ListRowDivider()
                    }
                }
            }
            .padding(.horizontal, AppTheme.contentPadding)
            .padding(.bottom, 24)
        }
        .background(AppTheme.surface)
        .navigationTitle("포스트잇")
        .confirmationDialog(
            "이 포스트잇을 완전히 삭제할까요?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { note in
            Button("완전 삭제", role: .destructive) { stickies.delete(note) }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("삭제하면 되돌릴 수 없습니다.")
        }
        .confirmationDialog(
            "선택한 포스트잇 \(selection.count)개를 완전히 삭제할까요?",
            isPresented: $showBulkDeleteConfirm
        ) {
            Button("\(selection.count)개 완전 삭제", role: .destructive) { deleteSelected() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제하면 되돌릴 수 없습니다.")
        }
    }

    // MARK: - 다중 선택 (§21.7)

    private func toggleSelectionMode() {
        selectionMode.toggle()
        if !selectionMode { selection.removeAll() }
    }

    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func selectAll(in groups: [(key: Date, label: String, notes: [StickyNote])]) {
        let all = Set(groups.flatMap { $0.notes.map(\.id) })
        // 이미 전부 선택돼 있으면 전체 해제(토글), 아니면 전체 선택.
        selection = (selection == all) ? [] : all
    }

    private func deleteSelected() {
        for note in stickies.archivedNotes where selection.contains(note.id) {
            stickies.delete(note)
        }
        selection.removeAll()
        selectionMode = false
    }

    // MARK: - 그룹핑

    /// 보관 노트를 닫은 논리적 날짜별로 묶는다 — 날짜 내림차순, 그룹 내부는 보관 시각 내림차순.
    private func archivedGroups() -> [(key: Date, label: String, notes: [StickyNote])] {
        let archived = stickies.archivedNotes
        let grouped = Dictionary(grouping: archived) { note in
            boundary.logicalDate(of: note.archivedAt ?? note.createdAt)
        }
        return grouped.keys.sorted(by: >).map { key in
            let notes = (grouped[key] ?? []).sorted {
                ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast)
            }
            return (key, dateLabel(key), notes)
        }
    }

    private func dateLabel(_ day: Date) -> String {
        if day == boundary.logicalToday() { return "오늘" }
        if day == boundary.logicalYesterday() { return "어제" }
        return Self.dayFormatter.string(from: day)
    }

    // MARK: - 미리보기

    private func isEmptyNote(_ note: StickyNote) -> Bool {
        note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 본문 첫 비어있지 않은 줄. 전부 비면 자리표시자.
    private func previewLine(_ note: StickyNote) -> String {
        let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "빈 노트" }
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        return firstLine
    }
}

// MARK: - 새 노트 버튼

/// 상단 '+ 새 포스트잇' — 커서 근처에 새 카드를 만들고 즉시 포커스(§19.1).
private struct StickyNewNoteButton: View {
    @State private var hovering = false

    var body: some View {
        Button {
            StickyNotesController.shared.createNote()
        } label: {
            HStack(spacing: AppTheme.rowSpacing) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.accent)
                Text("새 포스트잇")
                    .font(AppTheme.rowTitle)
                    .foregroundStyle(AppTheme.accent)
                Spacer()
            }
            .padding(.vertical, AppTheme.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius)
                    .fill(hovering ? AppTheme.hoverBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - 열린 노트 행

/// 열린 노트 한 행 — 클릭하면 해당 카드 창을 앞으로 가져와 포커스한다(§19.2).
private struct StickyOpenRow: View {
    let note: StickyNote
    let preview: String
    let isEmptyNote: Bool
    let onFocus: () -> Void
    let onArchive: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onFocus) {
            HStack(spacing: AppTheme.rowSpacing) {
                StickyColorDot(colorID: note.colorID)
                if note.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Text(preview)
                    .font(AppTheme.rowTitle)
                    .foregroundStyle(isEmptyNote ? AppTheme.textDisabled : AppTheme.textPrimary)
                    .italic(isEmptyNote)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if hovering {
                    StickyRowAction(systemImage: "archivebox", help: "보관", action: onArchive)
                }
            }
            .padding(.vertical, AppTheme.rowVerticalPadding)
            .frame(minHeight: AppTheme.rowMinHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius)
                    .fill(hovering ? AppTheme.hoverBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("창으로 이동") { onFocus() }
            Button("보관") { onArchive() }
        }
    }
}

// MARK: - 보관 노트 행

/// 보관 노트 한 행 — 다시 열기(reopen+창 생성) / 완전 삭제(확인 후).
private struct StickyArchivedRow: View {
    let note: StickyNote
    let preview: String
    let isEmptyNote: Bool
    let time: String
    /// §21.7: 다중 선택 모드면 행에 체크박스가 뜨고 탭이 선택 토글이 된다(다시 열기/삭제 액션은 숨김).
    let selectionMode: Bool
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let onReopen: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        rowContent
            .padding(.vertical, AppTheme.rowVerticalPadding)
            .frame(minHeight: AppTheme.rowMinHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius)
                    .fill(rowFill)
            )
            .onHover { hovering = $0 }
            // 선택 모드에서는 행 전체 탭이 선택 토글 — 개별 체크박스뿐 아니라 어디를 눌러도 담긴다.
            .modifier(TapWhen(active: selectionMode, action: onToggleSelect))
            .contextMenu {
                Button("다시 열기") { onReopen() }
                Button("완전 삭제", role: .destructive) { onDelete() }
            }
    }

    private var rowContent: some View {
        HStack(spacing: AppTheme.rowSpacing) {
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textDisabled)
            }
            StickyColorDot(colorID: note.colorID)
            Text(preview)
                .font(AppTheme.rowTitle)
                .foregroundStyle(isEmptyNote ? AppTheme.textDisabled : AppTheme.textSecondary)
                .italic(isEmptyNote)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if selectionMode {
                // 선택 모드에서는 시각적 잡음을 줄이려 시각만 보여준다(액션 숨김).
                Text(time)
                    .font(AppTheme.rowMeta)
                    .foregroundStyle(AppTheme.textDisabled)
            } else if hovering {
                StickyRowAction(systemImage: "arrow.up.forward.square", help: "다시 열기", action: onReopen)
                StickyRowAction(systemImage: "trash", help: "완전 삭제", action: onDelete)
            } else {
                Text(time)
                    .font(AppTheme.rowMeta)
                    .foregroundStyle(AppTheme.textDisabled)
            }
        }
    }

    private var rowFill: Color {
        if selectionMode && isSelected { return AppTheme.accent.opacity(0.10) }
        return hovering ? AppTheme.hoverBackground : Color.clear
    }
}

/// 조건부 탭 제스처 — 선택 모드에서만 행 전체 탭을 선택 토글로 쓴다(비선택 모드는 제스처 미부착).
private struct TapWhen: ViewModifier {
    let active: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if active {
            content.onTapGesture(perform: action)
        } else {
            content
        }
    }
}

// MARK: - 다중 선택 바 (§21.7)

/// 보관 목록 위의 다중 선택 컨트롤 — 선택 모드 진입/종료·모두 선택·선택 삭제.
private struct StickySelectionBar: View {
    let selectionMode: Bool
    let selectedCount: Int
    let onToggleMode: () -> Void
    let onSelectAll: () -> Void
    let onDeleteSelected: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleMode) {
                Label(selectionMode ? "취소" : "선택", systemImage: selectionMode ? "xmark" : "checkmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)

            if selectionMode {
                Button(action: onSelectAll) {
                    Text("모두 선택")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Button(action: onDeleteSelected) {
                    Label("선택 삭제\(selectedCount > 0 ? " (\(selectedCount))" : "")", systemImage: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedCount > 0 ? AppTheme.overdue : AppTheme.textDisabled)
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, AppTheme.rowVerticalPadding)
    }
}

// MARK: - 조각

/// 노트 색 점 — 색은 데이터 정체성이라 테마 무관 고정색(StickyPalette). 옅은 색도 표면 위에서
/// 보이도록 같은 계열 잉크로 얇은 테두리를 준다.
private struct StickyColorDot: View {
    let colorID: StickyColorID

    var body: some View {
        Circle()
            .fill(colorID.fill)
            .frame(width: 11, height: 11)
            .overlay(Circle().strokeBorder(colorID.ink.opacity(0.25), lineWidth: 0.5))
    }
}

/// 행 우측 아이콘 액션 버튼 (호버 시 노출).
private struct StickyRowAction: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
