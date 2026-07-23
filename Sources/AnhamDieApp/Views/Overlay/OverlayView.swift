import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 오버레이 카드 레이아웃 상수. 컨트롤러의 기본 크기 추정과 뷰가 공유한다.
/// v3(§11.2): 패널은 자유 리사이즈 — 카드가 패널을 채우고, 콘텐츠는 스크롤한다.
enum OverlayMetrics {
    static let defaultWidth: CGFloat = 260
    static let corner: CGFloat = 16
    static let hPadding: CGFloat = 14
    static let vPadding: CGFloat = 12
    static let rowSpacing: CGFloat = 8
    static let rowHeight: CGFloat = 24
    static let headerHeight: CGFloat = 22
    static let dividerHeight: CGFloat = 1
    /// 자유 리사이즈 하한/상한 (§11.2)
    static let minContentSize = CGSize(width: 200, height: 120)
    static let maxContentSize = CGSize(width: 520, height: 960)
}

/// acceptsFirstMouse를 열어, 앱이 비활성 상태여도 체크 원 첫 클릭이 바로 먹히게 한다.
/// (nonactivating 패널이라 클릭해도 현재 앱 포커스는 뺏지 않는다.)
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 카드가 패널 전체를 채운다 — 패널 크기(사용자 리사이즈·복원)가 곧 카드 크기 (§11.2).
struct OverlayRootView: View {
    var body: some View {
        OverlayCardView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 컴팩트 플로팅 오버레이 카드 (PLAN §3.2 + §11.2/§11.6).
/// 헤더(색 점 + "오늘 할 일" + 진행률) · 오늘 task 스크롤 목록 · 이월 요약.
/// 클릭 규칙(§11.2): 체크 원=완료 유예 토글 · 행(원 제외)=메인 창 · 헤더 클릭=메인 창 · 헤더 드래그=창 이동.
struct OverlayCardView: View {
    var body: some View {
        let context = AppContext.shared
        let settings = context.settings
        let grace = CompletionGraceController.shared
        // 관찰 지점: 논리적 하루 경계 통과 시 TriggerService가 갱신 → 열려 있는 오버레이가 재평가된다.
        _ = settings.currentLogicalDay
        // 표시 순서는 store 쿼리(전역 sortOrder)를 그대로 사용 — 자체 재정렬 금지 (§11.3).
        let tasks = context.store.todayTasks(boundary: context.dayBoundary)
        let total = tasks.count
        let completed = tasks.filter { $0.isCompleted || grace.isPending($0) }.count
        let rolloverCount = tasks.filter { $0.rolloverCount > 0 }.count

        return VStack(alignment: .leading, spacing: OverlayMetrics.rowSpacing) {
            header(total: total, completed: completed)
            Divider().opacity(0.5)
            if tasks.isEmpty {
                Text("오늘 할 일이 없어요")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: OverlayMetrics.rowSpacing) {
                        ForEach(tasks) { task in
                            OverlayTaskRow(task: task, store: context.store)
                        }
                    }
                }
            }
            if rolloverCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .semibold))
                    Text("이월됨 \(rolloverCount)개")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, OverlayMetrics.hPadding)
        .padding(.vertical, OverlayMetrics.vPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: OverlayMetrics.corner, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(settings.overlayOpacity)
        )
        .clipShape(RoundedRectangle(cornerRadius: OverlayMetrics.corner, style: .continuous))
    }

    // MARK: - 헤더

    // 헤더: 클릭 = 메인 창 열기, 드래그 = 창 이동 (§11.2). 두 동작은 OverlayHeaderInteraction이 구분한다.
    private func header(total: Int, completed: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 8, height: 8)
            Text("오늘 할 일")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 4)
            Text("\(completed)/\(total)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(height: OverlayMetrics.headerHeight)
        .contentShape(Rectangle())
        .overlay(OverlayHeaderInteraction(onClick: { MainWindowOpener.openMain() }))
        .help("클릭: 메인 창 · 드래그: 이동")
    }
}

/// 오버레이 한 행 (§11.2·§11.6). 체크 원=유예 토글, 나머지=메인 창, 드래그=수동 정렬.
private struct OverlayTaskRow: View {
    let task: TodoTask
    let store: TaskStore

    @State private var rowHeight: CGFloat = OverlayMetrics.rowHeight
    /// 드롭 삽입 위치 인디케이터(§12.7) — 메인 리스트와 동일한 드래그 경로(TaskReorderDropDelegate)를 공유한다.
    @State private var dropEdge: DropEdge?

    var body: some View {
        let grace = CompletionGraceController.shared
        // 유예 중(pending)이면 확정 전이라도 체크됨+취소선으로 그리되 목록에서 빼지 않는다 (§11.6).
        let checked = task.isCompleted || grace.isPending(task)

        HStack(alignment: .top, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    grace.toggleCompletion(of: task)
                }
            } label: {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(checked ? AppTheme.accent : Color.secondary)
            }
            .buttonStyle(.plain)

            // 제목은 폭에 맞춰 최대 2줄 줄바꿈, 넘치면 말줄임 + 툴팁 (§11.1/§11.2).
            Text(task.title)
                .font(.system(size: 12))
                .strikethrough(checked, color: .secondary)
                .foregroundStyle(checked ? .secondary : .primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(task.title)

            trailingBadges
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .overlay(TaskReorderIndicator(edge: dropEdge))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { rowHeight = $0 })
        // 행(원 제외) 클릭 = 메인 창 열기 (§11.2). 원은 위 Button이 먼저 소비한다.
        .onTapGesture { MainWindowOpener.openMain() }
        // 행 드래그 = 수동 정렬 (§11.2·§11.3). 메인 리스트와 같은 페이로드(.text task.id)·드롭 델리게이트를
        // 공유해 삽입 위치 인디케이터(§12.7)까지 동일하게 동작하고, 전역 sortOrder에 영속된다.
        .onDrag { taskDragItemProvider(task) }
        .onDrop(
            of: [.text],
            delegate: TaskReorderDropDelegate(
                target: task, store: store, rowHeight: rowHeight, edge: $dropEdge
            )
        )
        // 재정렬 스왑(§12.7): sortOrder 변화에만 반응해 새 위치로 미끄러지듯 이동.
        .reorderMotion(value: task.sortOrder)
    }

    private var trailingBadges: some View {
        HStack(spacing: 4) {
            if task.isRecurring {
                Image(systemName: "repeat")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if task.rolloverCount > 0 {
                rolloverBadge(task.rolloverCount)
            }
            if task.priority == .high {
                Circle()
                    .fill(AppTheme.priorityColor(.high))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.top, 1)
    }

    private func rolloverBadge(_ count: Int) -> some View {
        HStack(spacing: 1) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 8, weight: .bold))
            Text("\(count)")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.orange.opacity(0.15)))
    }
}

/// 헤더 상호작용을 AppKit에서 처리한다 (§11.2): 클릭=메인 창, 드래그=창 이동.
/// 배경 드래그 이동(isMovableByWindowBackground)은 꺼져 있으므로 창 이동은 여기서만 일어난다 —
/// 화면 좌표 델타로 패널 origin을 옮겨(창 이동 중에도 좌표계가 흔들리지 않음), 이동이 없으면 클릭으로 처리.
private struct OverlayHeaderInteraction: NSViewRepresentable {
    let onClick: () -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.onClick = onClick
    }

    final class DragView: NSView {
        var onClick: () -> Void = {}
        private var dragged = false
        private var lastScreen: NSPoint = .zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            dragged = false
            lastScreen = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let now = NSEvent.mouseLocation
            let dx = now.x - lastScreen.x
            let dy = now.y - lastScreen.y
            if !dragged && hypot(dx, dy) < 3 { return }
            dragged = true
            var origin = window.frame.origin
            origin.x += dx
            origin.y += dy
            window.setFrameOrigin(origin)
            lastScreen = now
        }

        override func mouseUp(with event: NSEvent) {
            if !dragged { onClick() }
        }
    }
}
