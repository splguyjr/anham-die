import AppKit
import SwiftUI

/// 메인 창 v2 (PLAN §10.1) — NavigationSplitView 사이드바 구조.
/// 좌: 스마트 뷰(해야할 일/백로그/완료/캘린더) + 태그 목록. 우: 선택별 detail 뷰.
/// v1 4탭 체제는 폐기 — 각 탭은 사이드바 뷰(ScheduleListView 등)로 이관됐다.
struct MainWindowView: View {
    @State private var selection: SidebarSection? = .todo

    var body: some View {
        // 관찰 지점: 논리적 하루 경계 통과 시 TriggerService가 갱신 → 열려 있는 메인 창이
        // 새 논리적 오늘 기준으로 재평가된다 (완료 항목 다음 날 숨김 PLAN §7 포함).
        let _ = AppContext.shared.settings.currentLogicalDay
        NavigationSplitView {
            MainSidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(
                    min: 160, ideal: AppTheme.sidebarIdealWidth, max: 240
                )
                .toolbar { sidebarToolbar }
        } detail: {
            detailView
        }
        .preferredColorScheme(.light)
        .frame(minWidth: 700, minHeight: 460)
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
        case .tag(let tag):
            ScheduleListView(tagFilter: tag)
        }
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
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
