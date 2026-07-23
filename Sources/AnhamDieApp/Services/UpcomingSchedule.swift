import Foundation

// "해야할 일" 뷰 v4 예정 리스트 (PLAN §12.4).
// 섹션을 ① 지난 · ② 오늘 · ③ 예정 3개로 축소하고, ③ 예정은 내일 이후 전체를
// 하나의 연속 시퀀스(UpcomingItem)로 묶되 각 날짜 그룹의 첫 항목에만 미니 구분선 라벨을 실어 보낸다.
// 소속 판정·정렬은 기존 scheduleSections(§10.1) 단일 소스를 그대로 재사용한다 — 규칙 중복 없음.

/// 예정 리스트의 한 행. 섹션이 아니라 리스트 내부 인라인 미니 구분선용 플래그를 포함한다 (PLAN §12.4).
struct UpcomingItem: Identifiable {
    let task: TodoTask
    /// 이 항목이 속한 논리적 날짜(자정 키). 항상 내일 이후.
    let day: Date
    /// 날짜 그룹의 첫 항목이면 true — 앞에 미니 날짜 구분선을 그린다.
    let isGroupStart: Bool
    /// isGroupStart일 때만 채워지는 구분선 라벨 ("내일 7/24", "7/28 (월)"). 그 외 nil.
    let dividerLabel: String?
    var id: UUID { task.id }
}

/// "해야할 일" 3섹션 데이터 (PLAN §12.4). past가 비면 UI에서 섹션 자체를 생략한다.
struct TodoSectionsV4 {
    let past: [TodoTask]
    let today: [TodoTask]
    let upcoming: [UpcomingItem]
}

extension TaskStore {
    /// 3섹션 전체를 한 번에 계산한다. 소속·정렬은 scheduleSections를 그대로 위임 —
    /// 지난(day==nil) → past, 오늘(day==today) → today, 그 외(day>today) → upcoming 평탄화.
    /// upcoming의 각 날짜 그룹 첫 항목에만 dividerLabel/isGroupStart를 세팅한다.
    /// 빈 날짜 그룹(예: 태스크 없는 내일)은 항목이 없으므로 구분선도 생기지 않는다.
    func todoSectionsV4(
        boundary: DayBoundaryService,
        tagFilter: Tag? = nil
    ) -> TodoSectionsV4 {
        let today = boundary.logicalToday()
        let tomorrow = boundary.calendar.date(byAdding: .day, value: 1, to: today)!
        let sections = scheduleSections(boundary: boundary, tagFilter: tagFilter)

        var past: [TodoTask] = []
        var todayTasks: [TodoTask] = []
        var upcoming: [UpcomingItem] = []

        for section in sections {
            guard let day = section.day else {
                past = section.tasks
                continue
            }
            if day == today {
                todayTasks = section.tasks
                continue
            }
            // day > today → 예정. 각 날짜 그룹의 첫 항목에만 구분선.
            for (index, task) in section.tasks.enumerated() {
                let isStart = index == 0
                upcoming.append(UpcomingItem(
                    task: task,
                    day: day,
                    isGroupStart: isStart,
                    dividerLabel: isStart
                        ? Self.upcomingDividerLabel(for: day, tomorrow: tomorrow, calendar: boundary.calendar)
                        : nil
                ))
            }
        }
        return TodoSectionsV4(past: past, today: todayTasks, upcoming: upcoming)
    }

    /// 지난 할 일(미완료 overdue·과거 scheduled 통합). 비면 빈 배열.
    func pastSection(boundary: DayBoundaryService, tagFilter: Tag? = nil) -> [TodoTask] {
        todoSectionsV4(boundary: boundary, tagFilter: tagFilter).past
    }

    /// 오늘 섹션.
    func todaySection(boundary: DayBoundaryService, tagFilter: Tag? = nil) -> [TodoTask] {
        todoSectionsV4(boundary: boundary, tagFilter: tagFilter).today
    }

    /// 내일 이후 전체를 단일 시퀀스로. 각 날짜 그룹 첫 항목에 미니 구분선(§12.4).
    func upcomingItems(boundary: DayBoundaryService, tagFilter: Tag? = nil) -> [UpcomingItem] {
        todoSectionsV4(boundary: boundary, tagFilter: tagFilter).upcoming
    }

    /// 미니 구분선 라벨: 내일은 "내일 M/d", 그 외는 "M/d (E)".
    nonisolated static func upcomingDividerLabel(for day: Date, tomorrow: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: tomorrow) {
            return "내일 " + UpcomingFormatters.shortDate.string(from: day)
        }
        return UpcomingFormatters.dayWithWeekday.string(from: day)
    }
}

enum UpcomingFormatters {
    /// "7/24"
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d"
        return f
    }()

    /// "7/28 (월)"
    static let dayWithWeekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d (E)"
        return f
    }()
}
