import AppKit
import SwiftUI

/// 메인 창 (PLAN §3.1) — Scribble 스타일 리스트.
/// 상단 색 점 + "AnhamDie" 타이틀 + … 메뉴, 인라인 추가 행, 뷰 전환 탭(오늘/예정/백로그/완료).
struct MainWindowView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case today = "오늘"
        case upcoming = "예정"
        case backlog = "백로그"
        case history = "완료"
        var id: String { rawValue }
    }

    @State private var selectedTab: Tab = .today
    @State private var newTaskTitle = ""
    @State private var expandedTaskID: UUID?
    @FocusState private var addFieldFocused: Bool

    private var store: TaskStore { AppContext.shared.store }
    private var boundary: DayBoundaryService { AppContext.shared.dayBoundary }

    private static let historyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E)"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider().overlay(MainTheme.divider)
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    if selectedTab != .history {
                        addRow
                        rowDivider
                    }
                    content
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(MainTheme.surface)
        .preferredColorScheme(.light)
        .frame(minWidth: 380, minHeight: 480)
    }

    // MARK: - 헤더

    private var header: some View {
        HStack(spacing: 8) {
            MainColorDot(color: MainTheme.accent, size: 11)
            Text("AnhamDie")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(MainTheme.ink)
            Spacer()
            Menu {
                Button("오버레이 표시/숨김") { OverlayController.shared.toggle() }
                Button("브리핑 열기") { BriefingController.shared.toggle() }
                Button("빠른 추가") { QuickAddController.shared.show() }
                Divider()
                SettingsLink { Text("설정…") }
                Divider()
                Button("종료") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MainTheme.inkSecondary)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - 탭

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                    expandedTaskID = nil
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? MainTheme.ink : MainTheme.inkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedTab == tab ? MainTheme.divider.opacity(0.9) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    // MARK: - 인라인 추가 행

    private var addPlaceholder: String {
        switch selectedTab {
        case .today: return "오늘 할 일 추가"
        case .upcoming: return "예정 할 일 추가"
        case .backlog: return "백로그에 추가"
        case .history: return ""
        }
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            Image(systemName: newTaskTitle.isEmpty ? "circle" : "circle.badge.plus")
                .font(.system(size: 18))
                .foregroundStyle(MainTheme.inkTertiary)
            TextField(addPlaceholder, text: $newTaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(MainTheme.ink)
                .focused($addFieldFocused)
                .onSubmit(addTask)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { addFieldFocused = true }
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let task = TodoTask(title: title)
        switch selectedTab {
        case .today:
            task.scheduledDate = boundary.scheduledToday()
        case .upcoming:
            task.dueDate = boundary.startOfLogicalDay(boundary.logicalToday())
        case .backlog, .history:
            break
        }
        task.sortOrder = (store.tasks.map(\.sortOrder).max() ?? 0) + 1
        store.addTask(task)
        newTaskTitle = ""
        addFieldFocused = true
    }

    // MARK: - 본문

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .today: todayContent
        case .upcoming: upcomingContent
        case .backlog: backlogContent
        case .history: historyContent
        }
    }

    private var todayContent: some View {
        let items = store.todayTasks(boundary: boundary)
        let active = items.filter { $0.isActive }
        let done = items.filter { $0.isCompleted }
        return VStack(spacing: 0) {
            if active.isEmpty && done.isEmpty {
                emptyState("오늘 할 일이 없습니다", system: "sun.max")
            }
            taskList(active)
            if !done.isEmpty {
                sectionHeader("완료됨")
                taskList(done)
            }
        }
    }

    private var upcomingContent: some View {
        let items = store.upcomingTasks()
        return VStack(spacing: 0) {
            if items.isEmpty {
                emptyState("예정된 할 일이 없습니다", system: "calendar")
            }
            taskList(items)
        }
    }

    private var backlogContent: some View {
        let items = store.backlogTasks()
        return VStack(spacing: 0) {
            if items.isEmpty {
                emptyState("백로그가 비어 있습니다", system: "tray")
            }
            taskList(items)
        }
    }

    private var historyContent: some View {
        let groups = historyGroups()
        let cancelled = store.cancelledTasks()
        return VStack(spacing: 0) {
            if groups.isEmpty && cancelled.isEmpty {
                emptyState("완료 기록이 없습니다", system: "checkmark.circle")
            }
            ForEach(groups, id: \.key) { group in
                sectionHeader(group.label)
                taskList(group.tasks)
            }
            if !cancelled.isEmpty {
                sectionHeader("취소됨")
                taskList(cancelled)
            }
        }
    }

    private func historyGroups() -> [(key: Date, label: String, tasks: [TodoTask])] {
        let completed = store.completedTasks()
        let grouped = Dictionary(grouping: completed) { task in
            boundary.logicalDate(of: task.completedAt ?? task.createdAt)
        }
        return grouped.keys.sorted(by: >).map { key in
            let tasks = (grouped[key] ?? []).sorted {
                ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
            }
            return (key, dateLabel(key), tasks)
        }
    }

    private func dateLabel(_ day: Date) -> String {
        if day == boundary.logicalToday() { return "오늘" }
        if day == boundary.logicalYesterday() { return "어제" }
        return Self.historyFormatter.string(from: day)
    }

    // MARK: - 공통 조각

    @ViewBuilder
    private func taskList(_ tasks: [TodoTask]) -> some View {
        ForEach(tasks) { task in
            MainTaskRow(
                task: task,
                store: store,
                boundary: boundary,
                isExpanded: expandedTaskID == task.id,
                onToggleExpand: { toggleExpand(task.id) }
            )
            rowDivider
        }
    }

    private func toggleExpand(_ id: UUID) {
        expandedTaskID = (expandedTaskID == id) ? nil : id
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(MainTheme.divider.opacity(0.7))
            .frame(height: 1)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(MainTheme.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }

    private func emptyState(_ message: String, system: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: system)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(MainTheme.inkTertiary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(MainTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
