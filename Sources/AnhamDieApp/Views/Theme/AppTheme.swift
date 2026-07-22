import SwiftUI

/// v2 단일 디자인 시스템 (PLAN §10.5) — 모든 뷰 모듈(메인/사이드바/캘린더/오버레이/퀵애드)이 공유한다.
/// v1 MainTheme을 흡수·확장했다. 다른 모듈과의 심볼 충돌을 피하려 Color 확장 대신 네임스페이스 사용.
enum AppTheme {
    // MARK: - 타이포 스케일 (크기·웨이트 대비 강화, 본문 상향 — §10.5)

    /// 섹션 헤더 (예: "오늘 7/23 (수)")
    static let sectionTitle = Font.system(size: 15, weight: .bold)
    /// 행 제목 본문 (v1 14 regular → 15 medium)
    static let rowTitle = Font.system(size: 15, weight: .medium)
    /// 행 보조 정보 (서브태스크 진행률, 날짜 메타 등)
    static let rowMeta = Font.system(size: 12, weight: .regular)
    /// 배지 텍스트 (D-day, 이월 ↺n, 개수)
    static let badge = Font.system(size: 11, weight: .bold)
    /// 사이드바 항목
    static let sidebarItem = Font.system(size: 13, weight: .medium)
    /// 창 타이틀
    static let windowTitle = Font.system(size: 17, weight: .bold)

    static let rowTitleSize: CGFloat = 15
    static let rowMetaSize: CGFloat = 12
    static let badgeSize: CGFloat = 11

    // MARK: - 컬러 (고대비 — §10.5)

    static let surface = Color.white
    /// 사이드바·패널 배경
    static let surfaceSecondary = Color(red: 0.965, green: 0.968, blue: 0.975)

    /// 기본 텍스트 (v1 ink보다 어둡게 — 대비 상향)
    static let textPrimary = Color(red: 0.08, green: 0.09, blue: 0.11)
    /// 보조 텍스트 (v1 inkSecondary 0.42 → 0.34 — 대비 상향)
    static let textSecondary = Color(red: 0.32, green: 0.34, blue: 0.38)
    /// 비활성/완료 텍스트
    static let textDisabled = Color(red: 0.58, green: 0.60, blue: 0.65)

    static let divider = Color(red: 0.90, green: 0.91, blue: 0.925)
    static let accent = Color(red: 0.15, green: 0.44, blue: 0.96)

    /// 행 호버 배경 (§10.5 호버 피드백 / §10.6 호버 인라인 액션의 바탕)
    static let hoverBackground = Color.black.opacity(0.05)
    /// 선택된 행/사이드바 항목 배경
    static let selectedBackground = accent.opacity(0.12)

    // MARK: - Due 컬러 (v1 MainTheme.dueColor 규칙 승계: 지남=빨강, 오늘=주황, 임박(≤3일)=노랑, 여유=회색)

    static let overdue = Color(red: 0.87, green: 0.20, blue: 0.16)
    static let dueToday = Color(red: 0.93, green: 0.48, blue: 0.08)
    static let dueSoon = Color(red: 0.78, green: 0.60, blue: 0.05)
    static let dueRelaxed = Color(red: 0.55, green: 0.57, blue: 0.62)

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
        case .low: return textDisabled
        }
    }

    /// "#RRGGBB" 태그 색상 파싱 (실패 시 중립 회색)
    static func tagColor(_ hex: String) -> Color {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard trimmed.count == 6, let value = UInt64(trimmed, radix: 16) else {
            return textDisabled
        }
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        return Color(red: r, green: g, blue: b)
    }

    // MARK: - 간격·행높이·코너 (§10.5 여백·행 높이 재조정)

    /// 콘텐츠 좌우 패딩
    static let contentPadding: CGFloat = 20
    /// 행 최소 높이 (v1 대비 상향 — 클릭 타깃·호버 액션 여유)
    static let rowMinHeight: CGFloat = 36
    /// 행 상하 패딩
    static let rowVerticalPadding: CGFloat = 8
    /// 행 내부 요소 간격 (체크박스-제목 등)
    static let rowSpacing: CGFloat = 10
    /// 섹션 사이 간격 (섹션 헤더 위 여백)
    static let sectionSpacing: CGFloat = 22
    /// 행 호버/선택 배경 코너
    static let rowCornerRadius: CGFloat = 6
    /// 카드/패널 코너
    static let cornerRadius: CGFloat = 10
    /// 사이드바 권장 폭
    static let sidebarIdealWidth: CGFloat = 190
    /// 우선순위·태그 색 점 크기 (v1 7 → 8, 가시성 상향)
    static let dotSize: CGFloat = 8

    // MARK: - v1 호환 별칭 (기존 뷰 마이그레이션 전까지 유지)

    static let ink = textPrimary
    static let inkSecondary = textSecondary
    static let inkTertiary = textDisabled
}

/// v1 호환: 기존 코드의 MainTheme 참조는 전부 AppTheme으로 위임된다 (§10.5 "MainTheme은 AppTheme으로 통합").
typealias MainTheme = AppTheme
