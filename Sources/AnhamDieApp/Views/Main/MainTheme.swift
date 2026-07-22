import SwiftUI

/// 메인 창 전용 디자인 토큰 (PLAN §3.1 — Scribble 스타일: 흰 배경, 넉넉한 여백, 깔끔한 타이포).
/// 다른 모듈과의 심볼 충돌을 피하려 Color 확장 대신 이 네임스페이스에 helper를 둔다.
enum MainTheme {
    static let surface = Color.white
    static let ink = Color(red: 0.12, green: 0.13, blue: 0.15)
    static let inkSecondary = Color(red: 0.42, green: 0.44, blue: 0.48)
    static let inkTertiary = Color(red: 0.66, green: 0.68, blue: 0.72)
    static let divider = Color(red: 0.91, green: 0.92, blue: 0.93)
    static let accent = Color(red: 0.20, green: 0.48, blue: 0.96)

    // Due 색상 규칙 (PLAN §3.1): 지남=빨강, 오늘=주황, 임박(≤3일)=노랑, 여유=회색
    static let overdue = Color(red: 0.90, green: 0.26, blue: 0.21)
    static let dueToday = Color(red: 0.95, green: 0.52, blue: 0.12)
    static let dueSoon = Color(red: 0.83, green: 0.66, blue: 0.10)
    static let dueRelaxed = Color(red: 0.62, green: 0.64, blue: 0.68)

    static func dueColor(dDay: Int) -> Color {
        if dDay < 0 { return overdue }
        if dDay == 0 { return dueToday }
        if dDay <= 3 { return dueSoon }
        return dueRelaxed
    }

    /// D-day 배지 텍스트. 0=D-DAY, 미래=D-n, 지남=D+n
    static func dDayText(_ dDay: Int) -> String {
        if dDay == 0 { return "D-DAY" }
        if dDay > 0 { return "D-\(dDay)" }
        return "D+\(-dDay)"
    }

    static func priorityColor(_ priority: Priority) -> Color {
        switch priority {
        case .high: return overdue
        case .normal: return accent
        case .low: return inkTertiary
        }
    }

    /// "#RRGGBB" 태그 색상 파싱 (실패 시 중립 회색)
    static func tagColor(_ hex: String) -> Color {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard trimmed.count == 6, let value = UInt64(trimmed, radix: 16) else {
            return inkTertiary
        }
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        return Color(red: r, green: g, blue: b)
    }
}
