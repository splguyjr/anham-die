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

    /// 포레스트 — 녹색 강조 라이트.
    static let forest = ThemePalette(
        id: "forest", displayName: "포레스트", isDark: false,
        background: rgb(0.90, 0.93, 0.88),
        surface: rgb(0.96, 0.98, 0.94),
        surfaceSecondary: rgb(0.92, 0.95, 0.90),
        textPrimary: rgb(0.10, 0.16, 0.12),
        textSecondary: rgb(0.28, 0.36, 0.30),
        textDisabled: rgb(0.50, 0.56, 0.50),
        divider: rgb(0.80, 0.86, 0.78),
        accent: rgb(0.18, 0.55, 0.34),
        overdue: rgb(0.80, 0.25, 0.18),
        dueToday: rgb(0.85, 0.50, 0.10),
        dueSoon: rgb(0.72, 0.58, 0.10),
        dueRelaxed: rgb(0.52, 0.56, 0.50)
    )

    /// 모노 — 무채색 UI. 단, due4색은 의미 유지 위해 유채색으로 남긴다(§13.2).
    static let mono = ThemePalette(
        id: "mono", displayName: "모노", isDark: false,
        background: rgb(0.94, 0.94, 0.94),
        surface: rgb(1, 1, 1),
        surfaceSecondary: rgb(0.96, 0.96, 0.96),
        textPrimary: rgb(0.10, 0.10, 0.10),
        textSecondary: rgb(0.34, 0.34, 0.34),
        textDisabled: rgb(0.60, 0.60, 0.60),
        divider: rgb(0.88, 0.88, 0.88),
        accent: rgb(0.20, 0.20, 0.22),
        overdue: rgb(0.82, 0.25, 0.20),
        dueToday: rgb(0.88, 0.52, 0.12),
        dueSoon: rgb(0.75, 0.62, 0.10),
        dueRelaxed: rgb(0.55, 0.55, 0.55)
    )

    /// 설정 갤러리 노출 순서.
    static let all: [ThemePalette] = [defaultLight, sepia, dark, forest, mono]

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
