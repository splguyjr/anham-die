import SwiftUI

/// 사이드바 선택 항목 (PLAN §10.1). 스마트 뷰 4개 + 태그 필터.
/// Tag는 참조 타입이라 동일성은 id 기준 — 스토어 리로드 후에도 같은 태그로 취급된다.
enum SidebarSection: Hashable, Identifiable {
    case todo
    case backlog
    case done
    case calendar
    case tag(Tag)

    static func == (lhs: SidebarSection, rhs: SidebarSection) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var id: String {
        switch self {
        case .todo: return "todo"
        case .backlog: return "backlog"
        case .done: return "done"
        case .calendar: return "calendar"
        case .tag(let tag): return "tag-\(tag.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .todo: return "해야할 일"
        case .backlog: return "백로그"
        case .done: return "완료"
        case .calendar: return "캘린더"
        case .tag(let tag): return tag.name
        }
    }

    var systemImage: String {
        switch self {
        case .todo: return "checklist"
        case .backlog: return "tray"
        case .done: return "checkmark.circle"
        case .calendar: return "calendar"
        case .tag: return "tag"
        }
    }

    /// 사이드바 상단 고정 스마트 뷰 (표시 순서 고정)
    static let smartSections: [SidebarSection] = [.todo, .backlog, .done, .calendar]
}

/// 좌측 사이드바 (PLAN §10.1): 스마트 뷰 4개 + 태그 목록(색 점).
struct MainSidebarView: View {
    @Binding var selection: SidebarSection?

    private var store: TaskStore { AppContext.shared.store }

    var body: some View {
        List(selection: $selection) {
            Section("보기") {
                ForEach(SidebarSection.smartSections) { section in
                    Label {
                        Text(section.title)
                            .font(AppTheme.sidebarItem)
                    } icon: {
                        Image(systemName: section.systemImage)
                            .foregroundStyle(AppTheme.accent)
                    }
                    .tag(section)
                }
            }
            if !store.tags.isEmpty {
                Section("태그") {
                    ForEach(store.tags) { tag in
                        Label {
                            Text(tag.name)
                                .font(AppTheme.sidebarItem)
                        } icon: {
                            Circle()
                                .fill(AppTheme.tagColor(tag.colorHex))
                                .frame(width: AppTheme.dotSize, height: AppTheme.dotSize)
                        }
                        .tag(SidebarSection.tag(tag))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
