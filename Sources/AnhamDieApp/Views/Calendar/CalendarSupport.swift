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
/// 색은 현재 테마에서 해석한다(§13.2 동적 테마) — 하드코딩 잔재 없이 프리셋에 적응하고
/// 렌더 배경(AppTheme.surface) 대비 AA(≥4.5:1, §10.5/§13.2)를 프리셋 전부에서 충족한다.
///
/// v7 §15.2 모노 계약(엄격 해석 — MonochromeContractTests로 고정): monochrome 팔레트에서는
/// 요일 관례색도 크롬이므로 무채로 흡수한다. 일·토 모두 textPrimary(무채 최고 농도) 강조 —
/// 일요일 빨강까지 내리는 이유는 "overdue 빨강만 유지"가 위험 신호 전용 계약이라, 전체 회색조
/// UI에 요일 관례 빨강이 남으면 overdue 신호와 구분되지 않기 때문. 극성(isDark)과 무관하게
/// textPrimary라 다크 무채 팔레트가 생겨도 자동 적응한다.
enum CalendarPalette {
    static var sunday: Color { sunday(in: AppTheme.palette) }

    /// 일요일 = 테마 빨강 토큰(overdue) 재사용 — 프리셋마다 값이 달라 세피아/포레스트에도
    /// 적응하고, 다크 프리셋에서 자동으로 밝아져 AA를 만족한다. 모노는 무채 강조(상단 계약).
    static func sunday(in palette: ThemePalette) -> Color {
        palette.monochrome ? palette.textPrimary : palette.overdue
    }

    static var saturday: Color { saturday(in: AppTheme.palette) }

    /// 토요일 = 테마 파랑. 전용 파랑 토큰이 없고 accent는 사용자 변경 가능(비파랑·저대비 가능)하므로,
    /// isDark 기준 밝기 2단으로 두어 밝은 표면·어두운 표면 양쪽에서 AA 대비를 확보한다.
    /// 모노는 유채 파랑 금지 — 무채 강조(상단 계약).
    static func saturday(in palette: ThemePalette) -> Color {
        if palette.monochrome { return palette.textPrimary }
        return palette.isDark
            ? Color(.sRGB, red: 0.42, green: 0.62, blue: 1.0, opacity: 1)
            : Color(.sRGB, red: 0.16, green: 0.38, blue: 0.78, opacity: 1)
    }

    static func weekdayColor(_ weekday: Int, base: Color) -> Color {
        weekdayColor(weekday, base: base, in: AppTheme.palette)
    }

    /// palette 주입 오버로드 — 전역 ThemeManager 없이 유닛 테스트 가능해야 한다.
    static func weekdayColor(_ weekday: Int, base: Color, in palette: ThemePalette) -> Color {
        switch weekday {
        case 1: return sunday(in: palette)
        case 7: return saturday(in: palette)
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

    /// "2026년 7월 23일 (수)" — 일간 뷰 헤더(§12.1).
    static let dayViewTitle: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일 (E)"
        return f
    }()

    /// "M월 d일"
    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일"
        return f
    }()

    /// "d일"
    private static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "d일"
        return f
    }()

    /// 주간 뷰 헤더 범위 "7월 19일 – 25일"(같은 달) 또는 "6월 29일 – 7월 5일"(다른 달) (§12.1).
    static func weekRangeTitle(start: Date, end: Date, calendar: Calendar) -> String {
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
        let startStr = monthDay.string(from: start)
        let endStr = (sameMonth ? dayOnly : monthDay).string(from: end)
        return "\(startStr) – \(endStr)"
    }
}
