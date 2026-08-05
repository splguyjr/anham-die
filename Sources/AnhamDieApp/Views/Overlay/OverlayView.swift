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
            // 다크 팔레트에서 반투명 재질·시스템 크롬이 팔레트 명암을 따르도록(§13.2, MainWindow와 동일 패턴).
            .preferredColorScheme(AppTheme.palette.isDark ? .dark : .light)
    }
}

// MARK: - 여유 칸 조건 (v13 §22.2)
// 선택·강조를 뷰 body에서 분리한 순수 로직 — 단위 테스트가 겨냥하는 지점(§22.4).

extension TaskStore {
    /// 오버레이 여유 칸에 노출할 '언젠가' 항목: 설정 on & 개수>0일 때만 전역 표시 순서 상위 count개.
    /// off거나 count≤0이면 빈 목록 — 섹션 자체가 사라진다(§22.2 설정 on/off·표시 개수).
    func overlaySomedayItems(show: Bool, count: Int) -> [TodoTask] {
        guard show, count > 0 else { return [] }
        return Array(somedayTasks().prefix(count))
    }

    /// 여유 칸 강조 여부: 오늘 미완료가 0개(다 끝냈거나 오늘 없음)면 true(§22.2).
    /// isDone에 완료 유예(pending)까지 완료로 넘겨 오버레이 체크 표시와 강조 시점을 일치시킨다.
    func isEmphasized(today tasks: [TodoTask], isDone: (TodoTask) -> Bool) -> Bool {
        tasks.allSatisfy(isDone)
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
        // v13 여유 칸 (§22.2): 선택·강조는 순수 헬퍼로 분리(§22.4 테스트 대상) — 여기선 호출만.
        let somedayItems = context.store.overlaySomedayItems(
            show: settings.overlaySomedayShow, count: settings.overlaySomedayCount)
        // 강조: 오늘 미완료 0(오늘 없음 포함). 유예 중(pending)도 완료로 쳐 오버레이 체크 표시와 일치.
        let todayAllDone = context.store.isEmphasized(today: tasks) {
            $0.isCompleted || grace.isPending($0)
        }

        return VStack(alignment: .leading, spacing: OverlayMetrics.rowSpacing) {
            header(total: total, completed: completed)
            Divider().opacity(0.5)
            if tasks.isEmpty {
                Text("오늘 할 일이 없어요")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
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
                .foregroundStyle(AppTheme.dueToday)
            }
            // v13 접이식 '여유' 섹션 (§22.2) — 오늘 목록 아래. 기존 오늘 목록 동작은 건드리지 않는다.
            if !somedayItems.isEmpty {
                OverlaySomedaySection(
                    items: somedayItems, store: context.store, emphasized: todayAllDone
                )
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
        // 우하단 리사이즈 그립(§21.3): 작은 시각 어포던스 + AppKit 히트영역으로 코너 드래그 리사이즈.
        .overlay(alignment: .bottomTrailing) { OverlayResizeGrip() }
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
                .foregroundStyle(AppTheme.textSecondary)
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
                    .foregroundStyle(checked ? AppTheme.accent : AppTheme.textSecondary)
            }
            .buttonStyle(.plain)

            // 제목은 폭에 맞춰 최대 2줄 줄바꿈, 넘치면 말줄임 + 툴팁 (§11.1/§11.2).
            Text(task.title)
                .font(.system(size: 12))
                .strikethrough(checked, color: AppTheme.textSecondary)
                .foregroundStyle(checked ? AppTheme.textSecondary : AppTheme.textPrimary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(task.title)

            // v5(§13.4): 태그 = 글자 칩(TagPill). 컴팩트 카드라 최대 2개 + "+N".
            RowTagPills(tags: store.tags(of: task), maxVisible: 2)
                .padding(.top, 1)

            trailingBadges
        }
        .padding(.leading, 5)
        .padding(.vertical, 2)
        // v5(§13.4): 우선순위 = 행 리딩 엣지 세로 색 막대(PriorityBar). 색점 방식 제거.
        .overlay(alignment: .leading) {
            PriorityBar(priority: task.priority, width: 2.5, minHeight: 12)
                .padding(.vertical, 1)
                .allowsHitTesting(false)
        }
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
                    .foregroundStyle(AppTheme.textSecondary)
            }
            if task.rolloverCount > 0 {
                rolloverBadge(task.rolloverCount)
            }
            // 우선순위는 v5에서 리딩 세로 막대(PriorityBar)로 옮겼다 — 여기서는 표시하지 않는다.
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
        .foregroundStyle(AppTheme.dueToday)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(Capsule().fill(AppTheme.dueToday.opacity(0.15)))
    }
}

/// v13 '여유' 섹션 (§22.2) — 오늘 목록 아래 접이식으로 '언젠가' 상위 N개를 노출한다.
/// 오늘 미완료가 0개(다 끝냈거나 애초에 없음)면 강조한다. 각 항목은 [오늘 하기]로 오늘 목록에 편입.
private struct OverlaySomedaySection: View {
    let items: [TodoTask]
    let store: TaskStore
    let emphasized: Bool

    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().opacity(0.5)
            header
            if expanded {
                if emphasized {
                    Text("여유가 있어요 — '언젠가'에서 하나 해볼까요?")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { task in
                        OverlaySomedayRow(task: task, store: store)
                    }
                }
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                Image(systemName: emphasized ? "sparkles" : "hourglass")
                    .font(.system(size: 10, weight: .semibold))
                Text("여유")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(emphasized ? AppTheme.accent : AppTheme.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(emphasized ? "오늘 할 일을 다 끝냈어요 · '언젠가' 목록" : "'언젠가' 목록 · 여유될 때 하기")
    }
}

/// '여유' 섹션 한 행 — 제목 + [오늘 하기]. 오늘 목록 드래그와 얽히지 않도록 드래그는 붙이지 않는다.
private struct OverlaySomedayRow: View {
    let task: TodoTask
    let store: TaskStore

    var body: some View {
        HStack(spacing: 6) {
            Text(task.title)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(task.title)
            Button {
                store.pullToToday(task, boundary: AppContext.shared.dayBoundary)
            } label: {
                Text("오늘 하기")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.accent.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("오늘 할 일로 가져오기")
        }
        .padding(.leading, 5)
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
        // 드래그 시작 시 (마우스 화면좌표 - 창 origin)을 1회 기록해 절대식 이동의 기준으로 삼는다.
        private var grabOffset: NSSize = .zero
        private var startScreen: NSPoint = .zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            dragged = false
            startScreen = NSEvent.mouseLocation
            if let window {
                grabOffset = NSSize(width: startScreen.x - window.frame.origin.x,
                                    height: startScreen.y - window.frame.origin.y)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let now = NSEvent.mouseLocation
            if !dragged {
                if hypot(now.x - startScreen.x, now.y - startScreen.y) < 3 { return }
                // 드래그 시작 — 종료(mouseUp)까지 windowDidMove의 위치 저장을 억제한다.
                OverlayController.shared.beginHeaderDrag()
                dragged = true
            }
            // 절대식: origin = 현재 마우스 - 최초 그랩 오프셋. 증분 델타 누적을 쓰지 않으므로
            // 리사이즈 재측정·클램프가 끼어들어도 매 이동이 그랩점을 그대로 유지한다(밀림 방지).
            window.setFrameOrigin(NSPoint(x: now.x - grabOffset.width,
                                          y: now.y - grabOffset.height))
        }

        override func mouseUp(with event: NSEvent) {
            if dragged {
                // 드래그 종료 시 최종 위치를 1회만 저장한다 (드래그 중 UserDefaults 쓰기 방지).
                OverlayController.shared.endHeaderDrag()
            } else {
                onClick()
            }
        }
    }
}

/// 우하단 리사이즈 그립 (§21.3). 대각선 눈금 시각 어포던스 위에 AppKit 히트영역을 얹어
/// 코너 드래그로 패널을 리사이즈한다(좌상단 고정). borderless 패널이라 시스템 그립이 안 보이는 걸 보완.
private struct OverlayResizeGrip: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GripGlyph()
                .allowsHitTesting(false)
            OverlayResizeHandle()
        }
        .frame(width: 18, height: 18)
        .padding(.trailing, 3)
        .padding(.bottom, 3)
        .help("드래그하여 크기 조절")
    }
}

/// 대각선 눈금 3줄로 그리는 클래식 리사이즈 그립 표시(시각 전용).
private struct GripGlyph: View {
    var body: some View {
        Canvas { context, size in
            for i in 0..<3 {
                let off = CGFloat(i) * 4 + 4
                var path = Path()
                path.move(to: CGPoint(x: size.width - off, y: size.height))
                path.addLine(to: CGPoint(x: size.width, y: size.height - off))
                context.stroke(path, with: .color(AppTheme.textSecondary.opacity(0.55)), lineWidth: 1.5)
            }
        }
    }
}

/// 코너 리사이즈 히트영역(§21.3). 좌상단을 고정한 채 우하단을 드래그해 프레임 크기를 바꾸고,
/// min/max(OverlayMetrics)로 클램프한다. 드래그 중엔 컨트롤러가 위치 저장을 억제하고 종료 시 1회 저장(에너지).
private struct OverlayResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ nsView: HandleView, context: Context) {}

    final class HandleView: NSView {
        private var initialFrame: NSRect = .zero
        private var startScreen: NSPoint = .zero
        private var resizing = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .crosshair)
        }

        override func mouseDown(with event: NSEvent) {
            resizing = false
            startScreen = NSEvent.mouseLocation
            if let window { initialFrame = window.frame }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            if !resizing {
                OverlayController.shared.beginHandleResize()
                resizing = true
            }
            let now = NSEvent.mouseLocation
            let dx = now.x - startScreen.x
            let dy = now.y - startScreen.y   // 화면 좌표(y↑): 아래로 끌면 dy<0 → 높이 증가
            let minS = OverlayMetrics.minContentSize
            let maxS = OverlayMetrics.maxContentSize
            let newWidth = min(max(initialFrame.width + dx, minS.width), maxS.width)
            let newHeight = min(max(initialFrame.height - dy, minS.height), maxS.height)
            // 좌상단(top-left) 고정: top = origin.y + height 를 유지하도록 origin.y를 보정.
            let top = initialFrame.origin.y + initialFrame.height
            let frame = NSRect(x: initialFrame.origin.x, y: top - newHeight,
                               width: newWidth, height: newHeight)
            window.setFrame(frame, display: true)
        }

        override func mouseUp(with event: NSEvent) {
            if resizing {
                resizing = false
                OverlayController.shared.endHandleResize()
            }
        }
    }
}
