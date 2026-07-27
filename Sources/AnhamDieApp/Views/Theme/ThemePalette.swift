import AppKit
import SwiftUI

/// v5 색상 팔레트 (PLAN §13.2) — 하나의 큐레이트 테마가 정의하는 색 세트.
/// 값타입이라 스냅샷/유닛 테스트가 쉽다. 타이포·간격은 AppTheme에 그대로 두고 '색'만 여기서 온다.
/// due4색(overdue/dueToday/dueSoon/dueRelaxed)은 테마마다 재정의 가능하되
/// 의미(지남=빨강·오늘=주황·임박=노랑·여유=회색 계열)는 유지한다.
struct ThemePalette: Identifiable, Equatable {
    let id: String
    let displayName: String
    /// 다크 계열 여부 — preferredColorScheme·호버/선택 오버레이 방향 결정에 쓴다.
    let isDark: Bool

    let background: Color
    let surface: Color
    let surfaceSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let textDisabled: Color
    let divider: Color
    let accent: Color
    let overdue: Color
    let dueToday: Color
    let dueSoon: Color
    let dueRelaxed: Color
    /// v7 무채 렌더 플래그 (§15.2) — true면 태그 칩·우선순위 막대 등 유채 데이터도 회색조로 해석한다
    /// (ThemeManager.resolvedTagColor/resolvedPriorityStyle). overdue 빨강만 위험 신호로 유지.
    /// 커스텀 테마는 항상 false. 기본값이 있어 기존 프리셋 이니셜라이저 시그니처는 그대로다.
    var monochrome: Bool = false

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    // MARK: - 프리셋

    /// 기본 — v2~v4 정적 AppTheme 색을 그대로 팔레트화한 라이트 테마(회귀 기준).
    static let defaultLight = ThemePalette(
        id: "default", displayName: "기본", isDark: false,
        background: rgb(0.95, 0.95, 0.96),
        surface: rgb(1, 1, 1),
        surfaceSecondary: rgb(0.965, 0.968, 0.975),
        textPrimary: rgb(0.08, 0.09, 0.11),
        textSecondary: rgb(0.32, 0.34, 0.38),
        textDisabled: rgb(0.58, 0.60, 0.65),
        divider: rgb(0.90, 0.91, 0.925),
        accent: rgb(0.15, 0.44, 0.96),
        overdue: rgb(0.87, 0.20, 0.16),
        dueToday: rgb(0.93, 0.48, 0.08),
        dueSoon: rgb(0.78, 0.60, 0.05),
        dueRelaxed: rgb(0.55, 0.57, 0.62)
    )

    /// 세피아 — 따뜻한 종이 톤.
    static let sepia = ThemePalette(
        id: "sepia", displayName: "세피아", isDark: false,
        background: rgb(0.93, 0.90, 0.82),
        surface: rgb(0.98, 0.96, 0.90),
        surfaceSecondary: rgb(0.95, 0.92, 0.84),
        textPrimary: rgb(0.22, 0.17, 0.11),
        textSecondary: rgb(0.40, 0.33, 0.24),
        textDisabled: rgb(0.60, 0.54, 0.44),
        divider: rgb(0.85, 0.80, 0.70),
        accent: rgb(0.70, 0.42, 0.13),
        overdue: rgb(0.80, 0.22, 0.15),
        dueToday: rgb(0.85, 0.45, 0.10),
        dueSoon: rgb(0.72, 0.55, 0.08),
        dueRelaxed: rgb(0.58, 0.52, 0.42)
    )

    /// 다크 — 저조도용. 텍스트/due 색을 대비 확보용으로 밝게 재정의.
    static let dark = ThemePalette(
        id: "dark", displayName: "다크", isDark: true,
        background: rgb(0.11, 0.11, 0.13),
        surface: rgb(0.16, 0.16, 0.19),
        surfaceSecondary: rgb(0.13, 0.13, 0.15),
        textPrimary: rgb(0.93, 0.94, 0.96),
        textSecondary: rgb(0.70, 0.72, 0.76),
        textDisabled: rgb(0.48, 0.50, 0.55),
        divider: rgb(0.26, 0.27, 0.30),
        accent: rgb(0.30, 0.56, 1.0),
        overdue: rgb(0.95, 0.38, 0.34),
        dueToday: rgb(0.98, 0.60, 0.22),
        dueSoon: rgb(0.90, 0.76, 0.24),
        dueRelaxed: rgb(0.55, 0.57, 0.62)
    )

    /// 포레스트 — 녹색 강조 라이트. v7: 배경 녹색조를 강화해(g가 r·b보다 뚜렷) 모노/오션과 확실히 구분.
    /// 대비: textPrimary/배경 12.3:1(AAA), textSecondary/배경 6.0:1(AA), accent/표면 4.4:1.
    static let forest = ThemePalette(
        id: "forest", displayName: "포레스트", isDark: false,
        background: rgb(0.87, 0.93, 0.85),
        surface: rgb(0.95, 0.985, 0.92),
        surfaceSecondary: rgb(0.91, 0.955, 0.89),
        textPrimary: rgb(0.09, 0.17, 0.11),
        textSecondary: rgb(0.26, 0.36, 0.29),
        textDisabled: rgb(0.48, 0.55, 0.49),
        divider: rgb(0.78, 0.85, 0.76),
        accent: rgb(0.15, 0.52, 0.31),
        overdue: rgb(0.80, 0.25, 0.18),
        dueToday: rgb(0.85, 0.50, 0.10),
        dueSoon: rgb(0.72, 0.58, 0.10),
        dueRelaxed: rgb(0.50, 0.55, 0.49)
    )

    /// 모노 — 진짜 무채색 UI (§15.2 재설계). 모든 슬롯 R=G=B(회백 배경·near-black 강조),
    /// monochrome=true로 태그 칩·우선순위 막대까지 회색조 렌더. 배경 0.90은 기본(0.95 쿨)·
    /// 하이콘트라스트(1.0)와 명도로 확실히 벌어져 "기본 vs 모노" 재발을 막는다.
    /// due는 무채 3단 농도(오늘 0.24 진함 → 임박 0.44 → 여유 0.62 옅음)로 긴급도 구분,
    /// overdue만 위험 신호로 빨강 유지(0.82/0.25/0.20 — CustomThemeTests.monoKeepsOverdueRed 계약).
    /// 대비: textPrimary/배경 14.0:1(AAA), textSecondary/배경 6.0:1(AA), accent/표면 14.7:1.
    static let mono = ThemePalette(
        id: "mono", displayName: "모노", isDark: false,
        background: rgb(0.90, 0.90, 0.90),
        surface: rgb(0.96, 0.96, 0.96),
        surfaceSecondary: rgb(0.93, 0.93, 0.93),
        textPrimary: rgb(0.10, 0.10, 0.10),
        textSecondary: rgb(0.33, 0.33, 0.33),
        textDisabled: rgb(0.58, 0.58, 0.58),
        divider: rgb(0.82, 0.82, 0.82),
        accent: rgb(0.13, 0.13, 0.13),
        overdue: rgb(0.82, 0.25, 0.20),
        dueToday: rgb(0.24, 0.24, 0.24),
        dueSoon: rgb(0.44, 0.44, 0.44),
        dueRelaxed: rgb(0.62, 0.62, 0.62),
        monochrome: true
    )

    /// 오션 — 블루그레이 라이트 + 딥블루 강조 (§15.3). 배경 b채널이 가장 높은 차가운 청회색.
    /// 대비: textPrimary/배경 13.4:1(AAA), textSecondary/배경 6.2:1(AA), accent/표면 7.4:1.
    static let ocean = ThemePalette(
        id: "ocean", displayName: "오션", isDark: false,
        background: rgb(0.87, 0.905, 0.965),
        surface: rgb(0.94, 0.965, 1.0),
        surfaceSecondary: rgb(0.90, 0.93, 0.98),
        textPrimary: rgb(0.07, 0.12, 0.18),
        textSecondary: rgb(0.26, 0.33, 0.42),
        textDisabled: rgb(0.50, 0.57, 0.65),
        divider: rgb(0.80, 0.86, 0.92),
        accent: rgb(0.05, 0.31, 0.60),
        overdue: rgb(0.85, 0.22, 0.18),
        dueToday: rgb(0.90, 0.50, 0.10),
        dueSoon: rgb(0.72, 0.58, 0.10),
        dueRelaxed: rgb(0.46, 0.55, 0.64)
    )

    /// 라벤더 — 연보라 라이트 + 바이올렛 강조 (§15.3). 배경 g채널이 가장 낮은(r·b 높은) 보라 기미.
    /// 오션(청)과는 저채널이 반대(오션=r 최저·라벤더=g 최저)라 육안으로 확실히 갈린다.
    /// 대비: textPrimary/배경 12.7:1(AAA), textSecondary/배경 6.1:1(AA), accent/표면 5.6:1.
    static let lavender = ThemePalette(
        id: "lavender", displayName: "라벤더", isDark: false,
        background: rgb(0.94, 0.88, 0.98),
        surface: rgb(0.975, 0.94, 1.0),
        surfaceSecondary: rgb(0.95, 0.90, 0.99),
        textPrimary: rgb(0.16, 0.11, 0.22),
        textSecondary: rgb(0.36, 0.30, 0.44),
        textDisabled: rgb(0.58, 0.53, 0.66),
        divider: rgb(0.87, 0.82, 0.93),
        accent: rgb(0.49, 0.26, 0.72),
        overdue: rgb(0.84, 0.24, 0.22),
        dueToday: rgb(0.88, 0.50, 0.12),
        dueSoon: rgb(0.74, 0.58, 0.12),
        dueRelaxed: rgb(0.56, 0.52, 0.64)
    )

    /// 미드나잇 — 순흑에 가까운 딥 다크(§15.3). 배경 0.02는 기존 다크(0.11)보다 뚜렷이 깊고,
    /// 표면 0.07도 다크 표면(0.16)과 명도로 벌어져 두 다크 테마가 구분된다. 강조는 순흑 위에서
    /// 튀도록 밝은 블루. 대비: textPrimary/배경 16.6:1(AAA), textSecondary/배경 8.1:1(AAA).
    static let midnight = ThemePalette(
        id: "midnight", displayName: "미드나잇", isDark: true,
        background: rgb(0.02, 0.02, 0.03),
        surface: rgb(0.07, 0.07, 0.09),
        surfaceSecondary: rgb(0.04, 0.04, 0.055),
        textPrimary: rgb(0.90, 0.91, 0.94),
        textSecondary: rgb(0.62, 0.64, 0.70),
        textDisabled: rgb(0.42, 0.44, 0.50),
        divider: rgb(0.16, 0.17, 0.20),
        accent: rgb(0.36, 0.62, 1.0),
        overdue: rgb(0.98, 0.42, 0.38),
        dueToday: rgb(1.0, 0.64, 0.26),
        dueSoon: rgb(0.92, 0.80, 0.30),
        dueRelaxed: rgb(0.55, 0.58, 0.64)
    )

    /// 하이콘트라스트 — 순백 배경/순흑 텍스트/굵은(짙은) 구분선, 접근성 최대 대비(§15.3).
    /// monochrome=false라 due·강조는 유채 유지하되 모두 순백 위에서 진하게. 배경 1.0은 기본(0.95)·
    /// 모노(0.90)와 명도로 갈린다. 대비: textPrimary/배경 21.0:1(최대), textSecondary/배경 16.6:1(AAA).
    static let highContrast = ThemePalette(
        id: "highContrast", displayName: "하이콘트라스트", isDark: false,
        background: rgb(1, 1, 1),
        surface: rgb(1, 1, 1),
        surfaceSecondary: rgb(0.90, 0.90, 0.90),
        textPrimary: rgb(0, 0, 0),
        textSecondary: rgb(0.12, 0.12, 0.12),
        textDisabled: rgb(0.38, 0.38, 0.38),
        divider: rgb(0.10, 0.10, 0.10),
        accent: rgb(0.0, 0.22, 0.85),
        overdue: rgb(0.80, 0.0, 0.0),
        dueToday: rgb(0.72, 0.34, 0.0),
        dueSoon: rgb(0.52, 0.40, 0.0),
        dueRelaxed: rgb(0.28, 0.28, 0.28)
    )

    /// 설정 갤러리 노출 순서 — 라이트 계열(기본→세피아→포레스트→오션→라벤더→모노→하이콘트라스트)
    /// 뒤에 다크 계열(다크→미드나잇). id는 모두 비-UUID 문자열이라 커스텀 이름공간과 충돌하지 않는다.
    static let all: [ThemePalette] = [
        defaultLight, sepia, forest, ocean, lavender, mono, highContrast, dark, midnight,
    ]

    /// id로 프리셋 조회. 미상/삭제된 id는 기본 팔레트로 폴백.
    static func preset(for id: String) -> ThemePalette {
        all.first { $0.id == id } ?? defaultLight
    }
}

/// "#RRGGBB" ↔ Color 변환 (테마 강조색 오버라이드·태그 색 파싱·설정 ColorPicker 왕복용).
enum ColorHex {
    /// 실패 시 nil — 호출측이 팔레트 기본값으로 폴백한다.
    static func color(_ hex: String) -> Color? {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard trimmed.count == 6, let value = UInt64(trimmed, radix: 16) else { return nil }
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Color → "#RRGGBB" (설정 ColorPicker 값 영속용). sRGB 기준.
    static func hex(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.gray
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
