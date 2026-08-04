import SwiftUI

/// 포스트잇 색 팔레트 (v10 §19.1) — 클래식 포스트잇 5색 + 각 색 위 텍스트 잉크색.
/// 포스트잇 색은 '데이터 정체성'이므로 AppTheme/ThemeManager를 경유하지 않는 고정 색값이다
/// — 모노 테마의 무채 규칙 예외(§19.1 명시). 테마가 바뀌어도 노트 색은 유지된다.
/// 잉크는 같은 색상 계열의 딥 톤 — 전 색 조합이 본문 텍스트 기준 WCAG AAA 7.0:1 이상
/// (StickyStoreTests의 대비 잠금 테스트가 회귀를 막는다).
extension StickyColorID {
    /// 카드 배경(본문) 색.
    var fill: Color {
        switch self {
        case .yellow: return Self.rgb(1.00, 0.949, 0.60)
        case .pink: return Self.rgb(1.00, 0.855, 0.88)
        case .mint: return Self.rgb(0.80, 0.945, 0.85)
        case .blue: return Self.rgb(0.80, 0.898, 1.00)
        case .lavender: return Self.rgb(0.898, 0.85, 1.00)
        }
    }

    /// 카드 위 텍스트 잉크색 — 색상 계열을 유지한 딥 톤 (fill 대비 7.0:1+).
    var ink: Color {
        switch self {
        case .yellow: return Self.rgb(0.24, 0.20, 0.04)
        case .pink: return Self.rgb(0.33, 0.09, 0.15)
        case .mint: return Self.rgb(0.05, 0.24, 0.14)
        case .blue: return Self.rgb(0.06, 0.17, 0.32)
        case .lavender: return Self.rgb(0.22, 0.14, 0.36)
        }
    }

    /// 상단 바 등 카드 내 보조 표면 — fill보다 살짝 진한 같은 계열 톤.
    /// 잉크색 10% 블렌드라 어떤 색에서도 fill과 명도차가 일정하다.
    var barTint: Color {
        ink.opacity(0.10)
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
