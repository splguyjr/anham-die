import SwiftUI

/// 메뉴바 팝오버 (PLAN §3.4): 오늘 요약(남은 개수) + 오늘 task 빠른 체크 목록 +
/// 브리핑 열기 / 오버레이 토글 / 메인 창 열기 / 설정 / 종료 버튼.
struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // 관찰 대상 store 프로퍼티를 body 안에서 읽어 SwiftUI 관찰을 성립시킨다.
        let context = AppContext.shared
        // 관찰 지점: 논리적 하루 경계 통과 시 TriggerService가 갱신 → 열려 있는 팝오버가 재평가된다.
        _ = context.settings.currentLogicalDay
        let today = context.dayBoundary.logicalToday()
        let tasks = context.store.tasks(on: today, boundary: context.dayBoundary)
        // 유예 중(pending)은 확정 전이라도 남은 개수에서 제외 — 오버레이 요약과 동일 규칙 (§11.6).
        let grace = CompletionGraceController.shared
        let remaining = tasks.filter { $0.isActive && !grace.isPending($0) }.count

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
                .fill(remaining == 0 ? Color.green : AppTheme.dueToday)
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

    // 완료 토글 단일 경로(§11.6): 유예 시작/취소·완료 해제·반복 다음 발생 생성(§11.5)이
    // 컨트롤러에서 처리된다 (task.markCompleted 직접 호출 금지 — 유예·반복이 여기서 일어난다).
    private func toggle(_ task: TodoTask) {
        withAnimation(.easeInOut(duration: 0.15)) {
            CompletionGraceController.shared.toggleCompletion(of: task)
        }
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
            MenuBarActionButton(title: "설정", systemImage: "gearshape") {
                SettingsWindowOpener.open(openSettings)
            }
            Divider()
                .padding(.vertical, 2)
            MenuBarActionButton(title: "종료", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 설정 창 열기

/// MenuBarExtra 창은 클릭해도 앱을 활성화하지 않으므로, showDockIcon=off(.accessory) 상태에서
/// bare SettingsLink로 열면 설정 창이 타 앱 뒤에 뜨거나 키 포커스가 없어
/// KeyboardShortcuts.Recorder가 녹화 모드에 진입하지 못한다 (스펙 §3.4).
/// 열기 전 activate + 창 생성 후 전면·키 지정까지 한 경로로 보장한다.
@MainActor
enum SettingsWindowOpener {
    static func open(_ openSettings: OpenSettingsAction) {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        bringToFront(retriesLeft: 10)
    }

    /// openSettings() 직후엔 설정 창이 아직 NSApp.windows에 없을 수 있어 짧게 재시도한다.
    private static func bringToFront(retriesLeft: Int) {
        DispatchQueue.main.async {
            if let window = settingsWindow() {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            } else if retriesLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    bringToFront(retriesLeft: retriesLeft - 1)
                }
            }
        }
    }

    private static func settingsWindow() -> NSWindow? {
        // SwiftUI Settings 씬 창 식별자는 "com_apple_SwiftUI_Settings_window" (비공개 관례라 contains로 매칭).
        NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }
    }
}

// MARK: - 하위 뷰

private struct MenuBarTaskRow: View {
    let task: TodoTask
    let toggle: (TodoTask) -> Void

    var body: some View {
        // 유예 중(pending)이면 확정 전이라도 체크됨+취소선으로 그리되 목록에서 빼지 않는다 (§11.6).
        let checked = task.isCompleted || CompletionGraceController.shared.isPending(task)

        HStack(spacing: 10) {
            Button {
                toggle(task)
            } label: {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(checked ? AppTheme.accent : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.callout)
                .strikethrough(checked, color: .secondary)
                .foregroundStyle(checked ? .secondary : .primary)
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

    private var text: String { AppTheme.dDayText(dDay) }

    private var color: Color { AppTheme.dueColor(dDay: dDay) }

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
