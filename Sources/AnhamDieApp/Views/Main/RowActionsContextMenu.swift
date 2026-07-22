import SwiftUI

/// 행 우클릭 컨텍스트 메뉴 (PLAN §10.6): 오늘로/내일로/날짜 선택/우선순위/태그/백로그로/삭제.
/// 날짜 선택·이름 편집·상세 토글은 상위(MainTaskRow) 상태를 건드리므로 클로저로 위임한다.
struct TaskRowContextMenu: View {
    let task: TodoTask
    let store: TaskStore
    let boundary: DayBoundaryService
    let onPickDate: () -> Void
    let onRename: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        Button {
            onToggleExpand()
        } label: {
            Label("상세 열기/닫기", systemImage: "chevron.down")
        }
        Button {
            onRename()
        } label: {
            Label("이름 편집", systemImage: "pencil")
        }

        Divider()

        if task.isActive {
            Button {
                RowAction.moveToToday(task, store: store, boundary: boundary)
            } label: {
                Label("오늘로", systemImage: "sun.max")
            }
            Button {
                RowAction.moveToTomorrow(task, store: store, boundary: boundary)
            } label: {
                Label("내일로", systemImage: "arrow.right")
            }
            Button {
                onPickDate()
            } label: {
                Label("날짜 선택…", systemImage: "calendar")
            }

            Menu {
                PriorityMenuContent(task: task, store: store)
            } label: {
                Label("우선순위", systemImage: "flag")
            }

            if !store.tags.isEmpty {
                Menu {
                    TagMenuContent(task: task, store: store)
                } label: {
                    Label("태그", systemImage: "tag")
                }
            }

            Button {
                RowAction.moveToBacklog(task, store: store)
            } label: {
                Label("백로그로", systemImage: "tray")
            }
        } else {
            Button {
                RowAction.reactivate(task, store: store)
            } label: {
                Label("되돌리기", systemImage: "arrow.uturn.backward")
            }
        }

        Divider()

        Button(role: .destructive) {
            RowAction.delete(task, store: store)
        } label: {
            Label("삭제", systemImage: "trash")
        }
    }
}
