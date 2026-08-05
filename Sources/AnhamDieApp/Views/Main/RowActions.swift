import SwiftUI

/// 행 액션의 단일 소스 (PLAN §10.6). 호버 인라인 액션·컨텍스트 메뉴·키보드가 모두 이 헬퍼를 호출한다.
/// 날짜 쓰기는 '자정 날짜 키' 규약(DayBoundaryService.scheduledDateValue)을 지킨다.
@MainActor
enum RowAction {
    static func moveToToday(_ task: TodoTask, store: TaskStore, boundary: DayBoundaryService) {
        task.scheduledDate = boundary.scheduledToday()
        store.notifyChanged()
    }

    static func moveToTomorrow(_ task: TodoTask, store: TaskStore, boundary: DayBoundaryService) {
        let tomorrow = boundary.calendar.date(byAdding: .day, value: 1, to: boundary.logicalToday())!
        task.scheduledDate = boundary.scheduledDateValue(for: tomorrow)
        store.notifyChanged()
    }

    static func moveToBacklog(_ task: TodoTask, store: TaskStore) {
        // §13.3 백로그 불변식: 백로그는 '미룬 날'이 없어 이월 이력 초기화(RolloverService.moveToBacklog와 동일).
        task.scheduledDate = nil
        task.rolloverCount = 0
        store.notifyChanged()
    }

    static func setPriority(_ task: TodoTask, _ priority: Priority, store: TaskStore) {
        task.priority = priority
        store.notifyChanged()
    }

    static func toggleTag(_ task: TodoTask, _ tag: Tag, store: TaskStore) {
        if task.tagIDs.contains(tag.id) {
            task.tagIDs.removeAll { $0 == tag.id }
        } else {
            task.tagIDs.append(tag.id)
        }
        store.notifyChanged()
    }

    static func reactivate(
        _ task: TodoTask,
        store: TaskStore,
        grace: CompletionGraceController = .shared // 테스트는 지역 컨트롤러 주입 (전역 컨테이너 비접근)
    ) {
        // 다른 표면에서 유예 중(pending)인 같은 task의 완료 예약을 먼저 무효화한다 — 되돌리기 직후
        // 유예 타이머 confirm이 재완료하며 주간 목표를 다시 +1하는 교차 표면 경합 방지 (§20.2).
        grace.cancelPending(for: task.id)
        // §20.2: 완료(completed) 되돌리기는 확정 시 +1됐던 연결 목표를 -1로 보정 (유예·브리핑 경로와 동일 규약).
        // 취소됨(cancelled) 되돌리기는 +1된 적 없으므로 제외 — reactivate가 status를 바꾸기 전에 판정한다.
        let wasCompleted = task.isCompleted
        task.reactivate()
        store.notifyChanged()
        if wasCompleted, let goalID = task.weeklyGoalID {
            store.decrementGoalCount(id: goalID)
        }
    }

    /// 취소됨/완료 → '오늘로 복구' (§21.8·§21.9). reactivate로 상태·주간 카운트를 되살린 뒤
    /// scheduledDate를 오늘로 옮겨 지난 날짜에 묻히지 않게 한다. 컨텍스트 메뉴·요약 카드 등 공용 단일 경로.
    static func restoreToToday(
        _ task: TodoTask,
        store: TaskStore,
        boundary: DayBoundaryService,
        grace: CompletionGraceController = .shared
    ) {
        reactivate(task, store: store, grace: grace)
        moveToToday(task, store: store, boundary: boundary)
    }

    static func delete(_ task: TodoTask, store: TaskStore) {
        store.removeTask(task)
    }
}

/// 우선순위 선택 메뉴 내용 (호버 Menu·컨텍스트 Menu 공용). 현재 값에 체크 표시.
struct PriorityMenuContent: View {
    let task: TodoTask
    let store: TaskStore

    var body: some View {
        // 높음 → 보통 → 낮음 순서 (⌘1/2/3와 일치)
        ForEach(Array(Priority.allCases.reversed()), id: \.self) { priority in
            Button {
                RowAction.setPriority(task, priority, store: store)
            } label: {
                if task.priority == priority {
                    Label(priority.displayName, systemImage: "checkmark")
                } else {
                    Text(priority.displayName)
                }
            }
        }
    }
}

/// 태그 토글 메뉴 내용 (호버 Menu·컨텍스트 Menu 공용). 포함된 태그에 체크 표시.
struct TagMenuContent: View {
    let task: TodoTask
    let store: TaskStore

    var body: some View {
        if store.tags.isEmpty {
            Text("태그 없음")
        } else {
            ForEach(store.tags) { tag in
                Button {
                    RowAction.toggleTag(task, tag, store: store)
                } label: {
                    if task.tagIDs.contains(tag.id) {
                        Label(tag.name, systemImage: "checkmark")
                    } else {
                        Text(tag.name)
                    }
                }
            }
        }
    }
}

/// 행 우측 호버 인라인 액션 (PLAN §10.6): 날짜 / 우선순위 / 태그 / 삭제.
/// 날짜는 상위(MainTaskRow)가 소유한 팝오버를 여는 트리거만 담당해 팝오버 앵커를 안정적으로 유지한다.
struct RowHoverActions: View {
    let task: TodoTask
    let store: TaskStore
    let boundary: DayBoundaryService
    @Binding var showDatePopover: Bool

    var body: some View {
        HStack(spacing: 1) {
            iconButton("calendar", help: "날짜") { showDatePopover = true }

            Menu {
                PriorityMenuContent(task: task, store: store)
            } label: {
                iconLabel("flag")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("우선순위")

            Menu {
                TagMenuContent(task: task, store: store)
            } label: {
                iconLabel("tag")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("태그")

            iconButton("trash", help: "삭제", tint: AppTheme.overdue) {
                RowAction.delete(task, store: store)
            }
        }
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        tint: Color = AppTheme.textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            iconLabel(systemName, tint: tint)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func iconLabel(_ systemName: String, tint: Color = AppTheme.textSecondary) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
    }
}
