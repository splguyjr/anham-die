import SwiftUI

// 사이드바 '주간 목표' 뷰의 이번 주 행·추가 행·편집 시트 (v11 §20.4 ①).
// 카운트 증감은 store.increment/decrementGoalCount, [오늘 하기]는 store.createLinkedTask(멱등),
// 루틴 전환은 goal.isRoutine 변경 + notifyChanged (스캐폴드 공용 API).

// MARK: - 이번 주 목표 행

struct WeeklyGoalRow: View {
    let goal: WeeklyGoal
    let store: TaskStore
    let boundary: DayBoundaryService
    /// 오늘 이미 연결 task가 있는가 (버튼 상태 표시용 — 부모가 store.tasks에서 산출).
    let hasTodayTask: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    private var isSingle: Bool { goal.targetCount <= 1 }

    var body: some View {
        HStack(spacing: AppTheme.rowSpacing) {
            progressIndicator

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(goal.title)
                        .font(AppTheme.rowTitle)
                        .foregroundStyle(goal.status == .dropped ? AppTheme.textDisabled : AppTheme.textPrimary)
                        .strikethrough(goal.status == .dropped)
                        .lineLimit(1)
                    if goal.isRoutine {
                        Image(systemName: weeklyGoalRoutineSymbol)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                            .help("매주 반복(루틴)")
                    }
                    if goal.status != .active {
                        WeeklyGoalStatusChip(goal: goal)
                    }
                }
                if !isSingle {
                    Text("\(goal.currentCount)/\(goal.targetCount)")
                        .font(AppTheme.rowMeta)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer(minLength: 8)

            if !isSingle {
                WeeklyGoalStepButton(systemImage: "minus", enabled: goal.currentCount > 0) {
                    store.decrementGoalCount(id: goal.id)
                }
                WeeklyGoalStepButton(systemImage: "plus", enabled: true) {
                    store.incrementGoalCount(id: goal.id)
                }
            }

            todayButton

            if hovering {
                iconAction(weeklyGoalRoutineSymbol,
                           help: goal.isRoutine ? "루틴 해제" : "루틴으로 전환",
                           active: goal.isRoutine) { toggleRoutine() }
                iconAction("pencil", help: "편집") { onEdit() }
                iconAction("trash", help: "삭제") { onDelete() }
            }
        }
        .padding(.vertical, AppTheme.rowVerticalPadding)
        .frame(minHeight: AppTheme.rowMinHeight)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius)
                .fill(hovering ? AppTheme.hoverBackground : Color.clear)
        )
        .onHover { hovering = $0 }
        .contextMenu {
            Button("오늘 하기") { createToday() }
            Button(goal.isRoutine ? "루틴 해제" : "루틴으로 전환") { toggleRoutine() }
            Button("편집") { onEdit() }
            Divider()
            Button("삭제", role: .destructive) { onDelete() }
        }
    }

    // MARK: 진행 표시 (단일형=체크, 횟수형=링)

    @ViewBuilder
    private var progressIndicator: some View {
        if isSingle {
            WeeklyGoalCheckButton(isChecked: goal.currentCount >= 1) { toggleSingle() }
        } else {
            WeeklyGoalRing(progress: goal.progress, isAchieved: goal.isAchieved)
        }
    }

    // MARK: [오늘 하기]

    private var todayButton: some View {
        Button { createToday() } label: {
            HStack(spacing: 4) {
                Image(systemName: hasTodayTask ? "checkmark.circle.fill" : "arrow.up.forward.circle")
                Text(hasTodayTask ? "오늘 목록" : "오늘 하기")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(hasTodayTask ? AppTheme.textSecondary : AppTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(AppTheme.accent.opacity(hasTodayTask ? 0.06 : 0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(hasTodayTask ? "이미 오늘 목록에 있습니다" : "오늘 할 일로 추가")
    }

    private func iconAction(
        _ systemImage: String, help: String, active: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(active ? AppTheme.accent : AppTheme.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: 액션

    private func createToday() {
        store.createLinkedTask(goal: goal, boundary: boundary)
    }

    private func toggleSingle() {
        if goal.currentCount >= 1 {
            store.decrementGoalCount(id: goal.id)
        } else {
            store.incrementGoalCount(id: goal.id)
        }
    }

    private func toggleRoutine() {
        goal.isRoutine.toggle()
        store.notifyChanged()
    }
}

// MARK: - 추가 행 (제목 · 횟수 · 루틴)

struct WeeklyGoalAddRow: View {
    @Binding var title: String
    @Binding var target: Int
    @Binding var routine: Bool
    let onAdd: () -> Void

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: AppTheme.rowSpacing) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(AppTheme.accent)

            TextField("새 주간 목표", text: $title)
                .textFieldStyle(.plain)
                .font(AppTheme.rowTitle)
                .foregroundStyle(AppTheme.textPrimary)
                .onSubmit { if canAdd { onAdd() } }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text(target <= 1 ? "1회" : "\(target)회")
                    .font(AppTheme.rowMeta)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(minWidth: 30, alignment: .trailing)
                Stepper("", value: $target, in: 1...99)
                    .labelsHidden()
            }
            .help("목표 횟수 (1회 = 단일형 체크)")

            Button { routine.toggle() } label: {
                Image(systemName: weeklyGoalRoutineSymbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(routine ? AppTheme.accent : AppTheme.textDisabled)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(routine ? AppTheme.accent.opacity(0.14) : Color.clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(routine ? "매주 반복(루틴) — 켜짐" : "매주 반복(루틴)")

            Button("추가", action: onAdd)
                .controlSize(.small)
                .disabled(!canAdd)
        }
        .padding(.vertical, AppTheme.rowVerticalPadding)
    }
}

// MARK: - 편집 시트

struct WeeklyGoalEditSheet: View {
    let goal: WeeklyGoal
    let store: TaskStore

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var target: Int
    @State private var routine: Bool

    init(goal: WeeklyGoal, store: TaskStore) {
        self.goal = goal
        self.store = store
        _title = State(initialValue: goal.title)
        _target = State(initialValue: goal.targetCount)
        _routine = State(initialValue: goal.isRoutine)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("목표 편집")
                .font(AppTheme.windowTitle)
                .foregroundStyle(AppTheme.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                TextField("제목", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if canSave { save() } }

                Stepper(value: $target, in: 1...99) {
                    Text(target <= 1 ? "목표 횟수: 1회 (단일형)" : "목표 횟수: \(target)회")
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Toggle(isOn: $routine) {
                    Text("매주 반복(루틴)")
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .toggleStyle(.switch)
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("저장") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(AppTheme.background)
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        goal.title = trimmed
        goal.targetCount = max(1, target)
        goal.isRoutine = routine
        store.notifyChanged()
        dismiss()
    }
}
