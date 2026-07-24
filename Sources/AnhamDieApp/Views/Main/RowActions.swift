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

    static func reactivate(_ task: TodoTask, store: TaskStore) {
        task.reactivate()
        store.notifyChanged()
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
