import SwiftUI

/// 행 상세: 메모, 서브태스크 체크리스트, 마감일(due) DatePicker, 태그 선택, 우선순위 (PLAN §3.1).
struct MainTaskDetailView: View {
    let task: TodoTask
    let store: TaskStore
    let boundary: DayBoundaryService

    @State private var newSubtaskTitle = ""

    private var settings: AppSettings { AppContext.shared.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            noteSection
            subtaskSection
            dueSection
            if !store.tags.isEmpty {
                tagSection
            }
            prioritySection
            actionBar
        }
        .padding(.top, 2)
    }

    // MARK: - 메모

    private var noteBinding: Binding<String> {
        Binding(
            get: { task.note },
            set: { task.note = $0; store.notifyChanged() }
        )
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("메모")
            TextField("메모 추가", text: noteBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(MainTheme.ink)
                .lineLimit(1...6)
                .padding(8)
                .background(MainTheme.divider.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 서브태스크

    private var subtaskSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("서브태스크")
            ForEach(task.subtasks) { subtask in
                subtaskRow(subtask)
            }
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(MainTheme.inkTertiary)
                TextField("하위 항목 추가", text: $newSubtaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(MainTheme.ink)
                    .onSubmit(addSubtask)
            }
        }
    }

    private func subtaskRow(_ subtask: Subtask) -> some View {
        HStack(spacing: 8) {
            MainCheckbox(isDone: subtask.isDone) {
                subtask.isDone.toggle()
                store.notifyChanged()
            }
            TextField("하위 항목", text: subtaskTitleBinding(subtask))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(subtask.isDone ? MainTheme.inkTertiary : MainTheme.ink)
                .strikethrough(subtask.isDone, color: MainTheme.inkTertiary)
            Button {
                task.subtasks.removeAll { $0.id == subtask.id }
                store.notifyChanged()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MainTheme.inkTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private func subtaskTitleBinding(_ subtask: Subtask) -> Binding<String> {
        Binding(
            get: { subtask.title },
            set: { subtask.title = $0; store.notifyChanged() }
        )
    }

    private func addSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let order = (task.subtasks.map(\.sortOrder).max() ?? 0) + 1
        task.subtasks.append(Subtask(title: title, sortOrder: order))
        newSubtaskTitle = ""
        store.notifyChanged()
    }

    // MARK: - 마감일 (due)

    // dueDate 쓰기 규약: '자정 날짜 키'(scheduledDateValue). 정규화·lastUsedDueDate 갱신은
    // DueDateControls가 담당하므로 여기서는 저장만 트리거한다.
    private var dueBinding: Binding<Date?> {
        Binding(
            get: { task.dueDate },
            set: { task.dueDate = $0; store.notifyChanged() }
        )
    }

    private var dueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                sectionLabel("마감일")
                if let due = task.dueDate {
                    MainDDayBadge(dDay: boundary.dDay(of: due))
                }
                Spacer()
            }
            DueDateControls(date: dueBinding, boundary: boundary, settings: settings)
        }
    }

    // MARK: - 태그

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("태그")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.tags) { tag in
                        tagChip(tag)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func tagChip(_ tag: Tag) -> some View {
        let selected = task.tagIDs.contains(tag.id)
        let color = MainTheme.tagColor(tag.colorHex)
        return Button {
            if selected {
                task.tagIDs.removeAll { $0 == tag.id }
            } else {
                task.tagIDs.append(tag.id)
            }
            store.notifyChanged()
        } label: {
            HStack(spacing: 5) {
                MainColorDot(color: color, size: 8)
                Text(tag.name)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? MainTheme.ink : MainTheme.inkSecondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(selected ? color.opacity(0.16) : MainTheme.divider.opacity(0.5))
            )
            .overlay(
                Capsule().strokeBorder(selected ? color.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 우선순위

    private var priorityBinding: Binding<Priority> {
        Binding(
            get: { task.priority },
            set: { task.priority = $0; store.notifyChanged() }
        )
    }

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("우선순위")
            Picker("", selection: priorityBinding) {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Text(priority.displayName).tag(priority)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - 액션 바

    private var isScheduledToday: Bool {
        guard let scheduled = task.scheduledDate else { return false }
        return boundary.logicalDay(ofStored: scheduled) == boundary.logicalToday()
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if task.isActive {
                if !isScheduledToday {
                    smallButton("오늘로", system: "sun.max") {
                        task.scheduledDate = boundary.scheduledToday()
                        store.notifyChanged()
                    }
                }
                if task.scheduledDate != nil {
                    smallButton("백로그로", system: "tray") {
                        task.scheduledDate = nil
                        store.notifyChanged()
                    }
                }
            } else {
                smallButton("되돌리기", system: "arrow.uturn.backward") {
                    task.reactivate()
                    store.notifyChanged()
                }
            }
            Spacer()
            Button {
                store.removeTask(task)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(MainTheme.overdue)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    private func smallButton(_ title: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: system)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(MainTheme.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(MainTheme.accent.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MainTheme.inkTertiary)
            .textCase(.uppercase)
    }
}
