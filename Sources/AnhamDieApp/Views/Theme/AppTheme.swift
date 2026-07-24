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

    // MARK: - 컬러 (v5 동적 테마 — PLAN §13.2)
    //
    // v2~v4의 정적 `static let` 색을 전부 "현재 테마"에서 해석하는 계산 프로퍼티로 전환했다.
    // 접근 시 ThemeManager.shared(→AppSettings의 @Observable 값)를 읽으므로, 뷰 body에서
    // AppTheme.* 를 읽는 것만으로 관찰이 등록돼 설정 변경 시 전 화면이 실시간 재평가된다.
    // 호출측(전 파일)은 손대지 않아도 자동으로 테마를 경유한다. 타이포·간격 토큰은 정적 유지.

    private static var theme: ThemeManager { ThemeManager.shared }
    /// 현재 팔레트(프리셋). 설정 갤러리·프리뷰가 직접 참조할 수 있다.
    static var palette: ThemePalette { theme.palette }

    /// 창/루트 배경
    static var background: Color { palette.background }
    static var surface: Color { palette.surface }
    /// 사이드바·패널 배경
    static var surfaceSecondary: Color { palette.surfaceSecondary }

    /// 기본 텍스트
    static var textPrimary: Color { palette.textPrimary }
    /// 보조 텍스트
    static var textSecondary: Color { palette.textSecondary }
    /// 비활성/완료 텍스트
    static var textDisabled: Color { palette.textDisabled }

    static var divider: Color { palette.divider }
    /// 강조색 — 팔레트 기본 + 사용자 ColorPicker 오버라이드 결합(§13.2)
    static var accent: Color { theme.accent }

    /// 행 호버 배경 (§10.5) — 다크 팔레트는 밝은 오버레이로 뒤집는다(대비 유지).
    static var hoverBackground: Color {
        palette.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
    /// 선택된 행/사이드바 항목 배경 — 강조색 기반, 다크는 조금 더 진하게.
    static var selectedBackground: Color { accent.opacity(palette.isDark ? 0.24 : 0.12) }

    // MARK: - Due 컬러 (지남=빨강, 오늘=주황, 임박(≤3일)=노랑, 여유=회색 — 테마별 재정의 가능하되 의미 유지)

    static var overdue: Color { palette.overdue }
    static var dueToday: Color { palette.dueToday }
    static var dueSoon: Color { palette.dueSoon }
    static var dueRelaxed: Color { palette.dueRelaxed }

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

    /// (v4 이하 색점용 — 유지) 우선순위 점 색.
    static func priorityColor(_ priority: Priority) -> Color {
        switch priority {
        case .high: return overdue
        case .normal: return accent
        case .low: return textDisabled
        }
    }

    /// v5 우선순위 세로 막대 색 (PLAN §13.4) — 높음=빨강(강), 보통=중립(얇은 회색), 낮음=흐림.
    static func priorityBarColor(_ priority: Priority) -> Color {
        switch priority {
        case .high: return overdue
        case .normal: return divider
        case .low: return textDisabled.opacity(0.5)
        }
    }

    /// "#RRGGBB" 태그 색상 파싱 (실패 시 중립 회색). 태그 색은 사용자 지정이라 테마 무관.
    static func tagColor(_ hex: String) -> Color {
        ColorHex.color(hex) ?? textDisabled
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

    static var ink: Color { textPrimary }
    static var inkSecondary: Color { textSecondary }
    static var inkTertiary: Color { textDisabled }
}

/// v1 호환: 기존 코드의 MainTheme 참조는 전부 AppTheme으로 위임된다 (§10.5 "MainTheme은 AppTheme으로 통합").
typealias MainTheme = AppTheme
