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
            recurrenceSection
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
            // §21.10: 이 바인딩의 set(nil)은 마감일 제거일 뿐(scheduledDate·백로그 무관)이라 중립 라벨을 준다.
            DueDateControls(
                date: dueBinding,
                boundary: boundary,
                settings: settings,
                clearLabel: "마감일 지우기",
                clearSystemImage: "xmark",
                clearHelp: "마감일을 제거합니다"
            )
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

    // v5(§13.4): 태그 = 글자 칩. 선택 UI라 토글은 유지하되 색점(MainColorDot)을 제거하고
    // TagPill과 일관된 태그색 글자 칩으로 통일한다(선택=태그색 강조, 비선택=중립).
    private func tagChip(_ tag: Tag) -> some View {
        let selected = task.tagIDs.contains(tag.id)
        let color = MainTheme.resolvedTagColor(hex: tag.colorHex)
        return Button {
            if selected {
                task.tagIDs.removeAll { $0 == tag.id }
            } else {
                task.tagIDs.append(tag.id)
            }
            store.notifyChanged()
        } label: {
            Text(tag.name)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? color : MainTheme.inkSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(selected ? color.opacity(0.16) : MainTheme.divider.opacity(0.5))
                )
                .overlay(
                    Capsule().strokeBorder(selected ? color.opacity(0.55) : .clear, lineWidth: 1)
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

    // MARK: - 반복 (PLAN §11.5)

    private enum RecurrenceKind: Int, CaseIterable, Identifiable {
        case none, daily, weekdays, weekly
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .none: return "반복 안 함"
            case .daily: return "매일"
            case .weekdays: return "평일"
            case .weekly: return "매주"
            }
        }
    }

    private static let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    private var currentKind: RecurrenceKind {
        switch task.recurrence {
        case .none: return .none
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .weekly: return .weekly
        }
    }

    /// weekly 규칙의 선택 요일 (Calendar.weekday 1=일 … 7=토). 다른 규칙이면 빈 집합.
    private var weeklyDays: Set<Int> {
        if case .weekly(let days) = task.recurrence { return days }
        return []
    }

    private var recurrenceKindBinding: Binding<RecurrenceKind> {
        Binding(get: { currentKind }, set: { setRecurrenceKind($0) })
    }

    private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("반복")
            Picker("", selection: recurrenceKindBinding) {
                ForEach(RecurrenceKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if currentKind == .weekly {
                weekdayPicker
            }
        }
    }

    private var weekdayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { index in
                    weekdayButton(index)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func weekdayButton(_ index: Int) -> some View {
        let weekday = index + 1
        let selected = weeklyDays.contains(weekday)
        return Button {
            toggleWeekday(weekday)
        } label: {
            Text(Self.weekdaySymbols[index])
                .font(.system(size: 12, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? Color.white : MainTheme.inkSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(selected ? MainTheme.accent : MainTheme.divider.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }

    private func setRecurrenceKind(_ kind: RecurrenceKind) {
        switch kind {
        case .none: task.recurrence = .none
        case .daily: task.recurrence = .daily
        case .weekdays: task.recurrence = .weekdays
        case .weekly:
            // 기존 선택 요일 유지, 비어 있으면 오늘 요일 하나로 시작 (빈 weekly는 다음 발생이 없음).
            let existing = weeklyDays
            if existing.isEmpty {
                let wd = boundary.calendar.component(.weekday, from: boundary.logicalToday())
                task.recurrence = .weekly([wd])
            } else {
                task.recurrence = .weekly(existing)
            }
        }
        store.notifyChanged()
    }

    private func toggleWeekday(_ weekday: Int) {
        var days = weeklyDays
        if days.contains(weekday) { days.remove(weekday) } else { days.insert(weekday) }
        task.recurrence = .weekly(days)
        store.notifyChanged()
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
                        // §13.3 백로그 불변식: RowAction 단일 헬퍼로 위임해 rolloverCount도 함께 리셋(↺ 배지 없음).
                        RowAction.moveToBacklog(task, store: store)
                    }
                }
            } else {
                smallButton("되돌리기", system: "arrow.uturn.backward") {
                    // §20.2: 완료 되돌리기 시 연결 주간 목표 -1을 함께 보정하려 단일 헬퍼로 위임.
                    RowAction.reactivate(task, store: store)
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
