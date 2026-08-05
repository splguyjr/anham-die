import SwiftUI

/// '언젠가' 패널 콘텐츠 (PLAN §22.2, ⌥⌘L) — 빠른 추가 · 목록(완료·[오늘 하기]·삭제·수동정렬).
/// 데이터 소스는 store.somedayTasks(). 오늘로 꺼내기는 store.pullToToday(_:boundary:).
/// 별도 사이드바 '언젠가' 뷰(메인 창)와 데이터는 공유하되, 여기선 어디서든 빠르게 열어 쓰는 컴팩트 표면이다.
struct SomedayPanelView: View {
    private var store: TaskStore { AppContext.shared.store }

    var body: some View {
        // 관찰 지점: 논리적 하루 경계 통과 시 TriggerService가 갱신 → 열려 있는 패널이 재평가된다.
        _ = AppContext.shared.settings.currentLogicalDay
        let items = store.somedayTasks()

        return VStack(alignment: .leading, spacing: 0) {
            header(count: items.count)
            ListAddRow(placeholder: "언젠가 할 일 추가") { title in
                store.addTaskApplyingInitialOrder(TodoTask(title: title, bucket: .someday))
            }
            .padding(.horizontal, 14)
            Divider().opacity(0.5)
            if items.isEmpty {
                ListEmptyState(
                    message: "여유될 때 꾸준히 해나갈 일을 모아두세요",
                    systemImage: "hourglass"
                )
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { task in
                            SomedayPanelRow(task: task, store: store)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.background)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.divider.opacity(0.6), lineWidth: 1)
        )
        // 다크 팔레트에서 시스템 크롬이 팔레트 명암을 따르도록(§13.2, 오버레이·메인 창과 동일 패턴).
        .preferredColorScheme(AppTheme.palette.isDark ? .dark : .light)
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "hourglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Text("언젠가")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(AppTheme.textSecondary.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 4)
            Button {
                SomedayPanelController.shared.hide()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("닫기 (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

/// '언젠가' 패널 한 행 — 완료 체크 · 제목(+메모 미리보기) · 태그 · 삭제(호버) · [오늘 하기] · 수동 정렬 드래그.
/// 드래그·드롭·완료 유예는 메인 리스트와 동일 경로(전역 sortOrder·CompletionGraceController)를 공유한다.
private struct SomedayPanelRow: View {
    let task: TodoTask
    let store: TaskStore

    @State private var isHovering = false
    @State private var rowHeight: CGFloat = 32
    @State private var dropEdge: DropEdge?

    var body: some View {
        let grace = CompletionGraceController.shared
        // 유예 중(pending)이면 확정 전이라도 체크됨+취소선으로 그리되 목록에서 빼지 않는다 (§11.6).
        let checked = task.isCompleted || grace.isPending(task)

        HStack(spacing: 8) {
            MainCheckbox(isDone: checked) {
                withAnimation(.easeInOut(duration: 0.15)) { grace.toggleCompletion(of: task) }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 13))
                    .strikethrough(checked, color: AppTheme.textSecondary)
                    .foregroundStyle(checked ? AppTheme.textSecondary : AppTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(task.title)
                if let preview = notePreview {
                    Text(preview)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RowTagPills(tags: store.tags(of: task), maxVisible: 2)

            // 삭제는 호버 시에만 보이되 레이아웃은 고정(항상 배치, 가시성만 토글 — 밀림 방지).
            Button(role: .destructive) {
                RowAction.delete(task, store: store)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .help("삭제")

            Button {
                store.pullToToday(task, boundary: AppContext.shared.dayBoundary)
            } label: {
                Text("오늘 하기")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppTheme.accent.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("오늘 할 일로 가져오기")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(minHeight: 32)
        // 우선순위 = 리딩 엣지 세로 색 막대(PriorityBar), 히트테스트 비활성 — 드래그/드롭은 아래로 전달.
        .overlay(alignment: .leading) {
            PriorityBar(priority: task.priority, width: 2.5, minHeight: 12)
                .allowsHitTesting(false)
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? AppTheme.hoverBackground : Color.clear)
        )
        .contentShape(Rectangle())
        .overlay(TaskReorderIndicator(edge: dropEdge))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { rowHeight = $0 })
        .onHover { isHovering = $0 }
        // 수동 정렬(§11.3): 메인 리스트와 같은 페이로드·드롭 델리게이트를 공유해 전역 sortOrder에 영속된다.
        .onDrag { taskDragItemProvider(task) }
        .onDrop(
            of: [.text],
            delegate: TaskReorderDropDelegate(
                target: task, store: store, rowHeight: rowHeight, edge: $dropEdge
            )
        )
        .reorderMotion(value: task.sortOrder)
    }

    private var notePreview: String? {
        guard AppContext.shared.settings.showNotePreview else { return nil }
        return NotePreview.firstLine(task.note)
    }
}
