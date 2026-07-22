import SwiftUI

/// 메뉴바 팝오버 (PLAN §3.4): 오늘 요약(남은 개수) + 오늘 task 빠른 체크 목록 +
/// 브리핑 열기 / 오버레이 토글 / 메인 창 열기 / 설정 / 종료 버튼.
struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // 관찰 대상 store 프로퍼티를 body 안에서 읽어 SwiftUI 관찰을 성립시킨다.
        let context = AppContext.shared
        let today = context.dayBoundary.logicalToday()
        let tasks = context.store.tasks(on: today, boundary: context.dayBoundary)
        let remaining = tasks.filter { $0.isActive }.count

        return VStack(alignment: .leading, spacing: 0) {
            header(remaining: remaining, total: tasks.count)
            Divider()
            taskList(tasks)
            Divider()
            actions()
        }
        .frame(width: 288)
    }

    // MARK: - 오늘 요약

    private func header(remaining: Int, total: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(remaining == 0 ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
            Text("오늘 할 일")
                .font(.headline)
            Spacer()
            Text(total == 0 ? "0개" : "남은 \(remaining)/\(total)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 빠른 체크 목록

    @ViewBuilder
    private func taskList(_ tasks: [TodoTask]) -> some View {
        if tasks.isEmpty {
            Text("오늘 할 일이 없어요")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(tasks) { task in
                        MenuBarTaskRow(task: task, toggle: toggle)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    private func toggle(_ task: TodoTask) {
        if task.isCompleted {
            task.reactivate()
        } else {
            task.markCompleted()
        }
        AppContext.shared.store.notifyChanged()
    }

    // MARK: - 버튼

    private func actions() -> some View {
        VStack(spacing: 0) {
            MenuBarActionButton(title: "브리핑 열기", systemImage: "sun.max") {
                NSApp.activate(ignoringOtherApps: true)
                BriefingController.shared.show()
            }
            MenuBarActionButton(title: "오버레이 토글", systemImage: "rectangle.on.rectangle") {
                OverlayController.shared.toggle()
            }
            MenuBarActionButton(title: "메인 창 열기", systemImage: "macwindow") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            SettingsLink {
                MenuBarActionLabel(title: "설정", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            Divider()
                .padding(.vertical, 2)
            MenuBarActionButton(title: "종료", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 하위 뷰

private struct MenuBarTaskRow: View {
    let task: TodoTask
    let toggle: (TodoTask) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                toggle(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(task.isCompleted ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.callout)
                .strikethrough(task.isCompleted, color: .secondary)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if task.rolloverCount > 0 {
                Label("\(task.rolloverCount)", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let due = task.dueDate {
                DDayBadge(dDay: AppContext.shared.dayBoundary.dDay(of: due))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct DDayBadge: View {
    let dDay: Int

    private var text: String {
        if dDay == 0 { return "D-day" }
        return dDay > 0 ? "D-\(dDay)" : "D+\(-dDay)"
    }

    private var color: Color {
        if dDay < 0 { return .red }        // 지남
        if dDay == 0 { return .orange }    // 오늘
        if dDay <= 3 { return .yellow }    // 임박
        return .secondary                  // 여유
    }

    var body: some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(color)
    }
}

private struct MenuBarActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuBarActionLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

private struct MenuBarActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
