import SwiftUI

/// 리스트 한 행: 체크박스 · 제목 · 우선순위/태그 색 점 · D-day 배지 · 이월 배지(↺n).
/// 헤더 탭 시 상세(MainTaskDetailView)를 펼친다 (PLAN §3.1).
struct MainTaskRow: View {
    let task: TodoTask
    let store: TaskStore
    let boundary: DayBoundaryService
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    private var subtaskProgress: String? {
        guard !task.subtasks.isEmpty else { return nil }
        let done = task.subtasks.filter { $0.isDone }.count
        return "\(done)/\(task.subtasks.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                MainTaskDetailView(task: task, store: store, boundary: boundary)
                    .padding(.leading, 28)
                    .padding(.trailing, 2)
                    .padding(.bottom, 10)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            MainCheckbox(isDone: task.isCompleted, action: toggleDone)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 14))
                    .foregroundStyle(task.isCompleted ? MainTheme.inkTertiary : MainTheme.ink)
                    .strikethrough(task.isCompleted, color: MainTheme.inkTertiary)
                    .lineLimit(1)
                if let progress = subtaskProgress {
                    HStack(spacing: 4) {
                        Image(systemName: "checklist")
                            .font(.system(size: 9))
                        Text(progress)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(MainTheme.inkTertiary)
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 5) {
                if task.priority != .normal {
                    MainColorDot(color: MainTheme.priorityColor(task.priority))
                }
                ForEach(store.tags(of: task)) { tag in
                    MainColorDot(color: MainTheme.tagColor(tag.colorHex))
                }
            }

            if task.rolloverCount > 0 {
                MainRolloverBadge(count: task.rolloverCount)
            }
            if let due = task.dueDate {
                MainDDayBadge(dDay: boundary.dDay(of: due))
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpand)
    }

    private func toggleDone() {
        if task.isCompleted {
            task.reactivate()
        } else {
            task.markCompleted()
        }
        store.notifyChanged()
    }
}
