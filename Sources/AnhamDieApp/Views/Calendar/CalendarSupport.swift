import SwiftUI
import UniformTypeIdentifiers

// 캘린더 모듈 공용 조각 (PLAN §10.2): 드래그 페이로드·월 레이아웃·요일 색상·포매터.

extension UTType {
    /// 캘린더 셀 간 task 드래그 페이로드 타입 (앱 내부 전용).
    static let anhamDieCalendarTask = UTType(exportedAs: "com.splguyjr.anhamdie.calendar-task")
}

/// task를 다른 날짜 셀로 드래그할 때 옮기는 페이로드 — task id만 전달하고, 드롭 시 store에서 조회한다.
struct CalendarTaskDrag: Codable, Transferable {
    let taskID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .anhamDieCalendarTask)
    }
}

/// 특정 달을 7열 그리드로 펼친 레이아웃. 이전/다음 달 잔여일을 채워 완전한 주 단위로 만든다.
struct MonthLayout {
    /// 표시 달의 1일 자정
    let monthStart: Date
    /// 그리드에 놓일 날짜들(자정 정규화). 앞뒤로 이전/다음 달 잔여일 포함, 항상 7의 배수.
    let days: [Date]
    let rows: Int
    /// firstWeekday 기준으로 회전된 요일 약칭 (예: ["일","월",...,"토"])
    let weekdaySymbols: [String]

    /// index 0 = 일요일(weekday 1). 시스템 로케일과 무관하게 UI는 한국어 요일로 표기한다.
    private static let koreanWeekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    init(containing date: Date, calendar: Calendar) {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
            ?? calendar.startOfDay(for: date)
        self.monthStart = monthStart

        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart) ?? monthStart
        let totalUsed = leading + dayCount
        let rowCount = Int((Double(totalUsed) / 7.0).rounded(.up))
        self.rows = rowCount
        self.days = (0..<(rowCount * 7)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart).map(calendar.startOfDay)
        }

        self.weekdaySymbols = (0..<7).map {
            Self.koreanWeekdaySymbols[(calendar.firstWeekday - 1 + $0) % 7]
        }
    }

    func isInMonth(_ day: Date, calendar: Calendar) -> Bool {
        calendar.isDate(day, equalTo: monthStart, toGranularity: .month)
    }
}

/// 요일 색상 규약 (한국 달력 관례): 일요일 빨강, 토요일 파랑, 평일은 기본색.
enum CalendarPalette {
    static let sunday = Color(red: 0.82, green: 0.26, blue: 0.22)
    static let saturday = Color(red: 0.20, green: 0.42, blue: 0.80)

    static func weekdayColor(_ weekday: Int, base: Color) -> Color {
        switch weekday {
        case 1: return sunday
        case 7: return saturday
        default: return base
        }
    }
}

enum CalendarFormatters {
    /// "2026년 7월"
    static let monthTitle: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월"
        return f
    }()

    /// "7월 23일 (수)"
    static let dayPanelTitle: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E)"
        return f
    }()
}
