import AppKit
import SwiftUI

/// 메인 창 v2 (PLAN §10.1) — NavigationSplitView 사이드바 구조.
/// 좌: 스마트 뷰(해야할 일/백로그/완료/캘린더) + 태그 목록. 우: 선택별 detail 뷰.
/// v1 4탭 체제는 폐기 — 각 탭은 사이드바 뷰(ScheduleListView 등)로 이관됐다.
struct MainWindowView: View {
    @State private var selection: SidebarSection?
    // 사이드바 접힘 상태 (PLAN §12.3) — 접힘=.detailOnly, 펼침=.all. sidebarCollapsed와 동기화.
    @State private var columnVisibility: NavigationSplitViewVisibility

    // 마지막 선택 사이드바 뷰를 복원한다 (PLAN §11.7) — 없거나 해석 불가면 기본 '해야할 일'.
    // 사이드바 접힘 상태도 복원한다 (PLAN §12.3).
    init() {
        let restored = SidebarSection.restore(
            fromID: MainWindowState.restoreSelectionRawValue(),
            store: AppContext.shared.store
        )
        _selection = State(initialValue: restored ?? .todo)
        _columnVisibility = State(
            initialValue: AppContext.shared.settings.sidebarCollapsed ? .detailOnly : .all
        )
    }

    var body: some View {
        // 관찰 지점: 논리적 하루 경계 통과 시 TriggerService가 갱신 → 열려 있는 메인 창이
        // 새 논리적 오늘 기준으로 재평가된다 (완료 항목 다음 날 숨김 PLAN §7 포함).
        let _ = AppContext.shared.settings.currentLogicalDay
        // 관찰 지점: 설정>태그에서 삭제 시 selection 정합성 검증(onChange) — body가 tags를
        // 읽어야 스토어 변경이 이 뷰의 재평가·onChange로 이어진다.
        let tagIDs = AppContext.shared.store.tags.map(\.id)
        // 접힘 상태를 columnVisibility로 제어한다 (PLAN §12.3) — 접으면 detail(캘린더·리스트)이 전폭 확보.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MainSidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(
                    min: 160, ideal: AppTheme.sidebarIdealWidth, max: 240
                )
        } detail: {
            detailView
        }
        // 사이드바 토글은 표준 macOS 토글 하나로 통일(§13.1) — 커스텀 sidebar.left 버튼 제거.
        // 네이티브 토글이 columnVisibility를 바꾸면 아래 onChange가 접힘 상태를 영속한다.
        .toolbar { mainToolbar }
        // 팔레트가 다크면 다크 스킴으로(§13.2) — 시스템 크롬까지 테마와 일치.
        .preferredColorScheme(AppContext.shared.theme.palette.isDark ? .dark : .light)
        .frame(minWidth: 700, minHeight: 460)
        // 창 위치·크기 저장/복원 (PLAN §11.7): 표시 직전 복원, 이동/리사이즈 시 저장.
        .background(MainWindowConfigurator())
        .onChange(of: tagIDs) {
            if case .tag(let tag) = selection,
               !AppContext.shared.store.tags.contains(where: { $0.id == tag.id }) {
                selection = .todo
            }
        }
        // 선택 뷰 저장 (PLAN §11.7) — rawValue = SidebarSection.id.
        .onChange(of: selection) {
            MainWindowState.saveSelection((selection ?? .todo).id)
        }
        // 접힘 상태 저장 (PLAN §12.3) — 접힘=detailOnly. 명시적 토글·시스템 재배치 양쪽을 포착.
        .onChange(of: columnVisibility) {
            AppContext.shared.settings.sidebarCollapsed = (columnVisibility == .detailOnly)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .todo {
        case .todo:
            ScheduleListView()
        case .backlog:
            BacklogListView()
        case .done:
            DoneListView()
        case .calendar:
            CalendarView()
        case .weeklyGoals:
            WeeklyGoalsView()
        case .stickies:
            StickiesListView()
        case .tag(let tag):
            ScheduleListView(tagFilter: tag)
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem {
            Menu {
                Button("오버레이 표시/숨김") { OverlayController.shared.toggle() }
                Button("브리핑 열기") { BriefingController.shared.toggle() }
                Button("빠른 추가") { QuickAddController.shared.show() }
                Divider()
                SettingsLink { Text("설정…") }
                Divider()
                Button("종료") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
        }
    }
}

/// 메인 창 NSWindow에 붙어 프레임 복원/저장을 연결한다 (PLAN §11.7).
/// 표시 직전 저장된 프레임으로 setFrame(1회), 이동/리사이즈 시 MainWindowState.saveFrame.
struct MainWindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.attach(to: nsView.window) }
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var window: NSWindow?
        private var restored = false
        private var observers: [NSObjectProtocol] = []

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            self.window = window

            if !restored {
                restored = true
                if let frame = MainWindowState.restoreFrame() {
                    window.setFrame(frame, display: true)
                }
            }

            // OverlayController와 동일하게 리사이즈는 종료 시점(didEndLiveResize)에만 저장한다 —
            // 라이브 드래그 중 didResize마다 저장하는 잦은 쓰기를 피한다. 이동은 didMove, 닫힘은 willClose로 마무리.
            let center = NotificationCenter.default
            observers.forEach { center.removeObserver($0) }
            let names: [Notification.Name] = [
                NSWindow.didMoveNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.willCloseNotification
            ]
            observers = names.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak window] _ in
                    guard let window else { return }
                    MainActor.assumeIsolated { MainWindowState.saveFrame(window.frame) }
                }
            }
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}
