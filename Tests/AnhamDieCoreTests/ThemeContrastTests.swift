import Foundation
import SwiftUI
import Testing
@testable import AnhamDieApp

// v7 3R(§15.3 재점검) 대비 잠금 — 주석 실측치가 아니라 WCAG 상대휘도 계산 자체를 테스트로 고정.
// 계약:
//  ① overdue: 9프리셋 전부 표면 5.5:1+ · D-day 캡슐(색 14% 블렌드 위 글자) 4.5:1+ (11pt semibold AA)
//  ② 글자가 올라가는 중립 캡슐(이월·카운트 배지·"+N" 칩)은 글자색(textSecondary) 12% 틴트 관례 —
//     divider 채움 재사용 금지: 하이콘트라스트의 근흑 divider(굵은 구분선 목적)에서 1.8:1로 붕괴
//  ③ due 사다리: dueToday 캡슐 4.5:1+ 전 프리셋 · dueSoon 캡슐 4.5:1+(모노는 농도 사다리라 표면 직접
//     4.5:1+) · dueRelaxed 캡슐 3.0:1+(대형/보조 하한, §15.3 1R 모노 0.50 보정 회귀 금지)
//  ④ 표면 위 본문(§13.2 퀵애드 고불투명 패널 등): textPrimary 7.0:1+(AAA) · textSecondary 4.5:1+(AA)
//     전 프리셋 — 팔레트 색값 조정이 표면 위 텍스트 가독을 회귀시키지 못하게 잠근다

@Suite("테마 대비 잠금 (WCAG)")
struct ThemeContrastTests {
    private struct RGB { let r, g, b: Double }

    private func rgb(_ color: Color) -> RGB {
        let hex = ColorHex.hex(color)
        let value = UInt64(hex.dropFirst(), radix: 16)!
        return RGB(
            r: Double((value & 0xFF0000) >> 16) / 255,
            g: Double((value & 0x00FF00) >> 8) / 255,
            b: Double(value & 0x0000FF) / 255
        )
    }

    private func luminance(_ c: RGB) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    private func ratio(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func blend(_ fg: RGB, _ alpha: Double, over bg: RGB) -> RGB {
        RGB(
            r: fg.r * alpha + bg.r * (1 - alpha),
            g: fg.g * alpha + bg.g * (1 - alpha),
            b: fg.b * alpha + bg.b * (1 - alpha)
        )
    }

    @Test("overdue — 9프리셋 전부 표면 5.5:1+ · D-day 캡슐 4.5:1+")
    func overdueContrast() {
        for p in ThemePalette.all {
            let surface = rgb(p.surface)
            let overdue = rgb(p.overdue)
            #expect(ratio(overdue, surface) >= 5.5, "\(p.id) overdue/표면")
            #expect(ratio(overdue, blend(overdue, 0.14, over: surface)) >= 4.5, "\(p.id) overdue/캡슐")
        }
    }

    @Test("중립 캡슐 관례 — textSecondary 12% 틴트 위 글자 4.5:1+ (표면·배경·보조표면 전부)")
    func neutralCapsuleContrast() {
        for p in ThemePalette.all {
            let text = rgb(p.textSecondary)
            for base in [rgb(p.surface), rgb(p.background), rgb(p.surfaceSecondary)] {
                #expect(ratio(text, blend(text, 0.12, over: base)) >= 4.5, "\(p.id)")
            }
        }
    }

    @Test("표면 위 본문 — textPrimary 7.0:1+(AAA) · textSecondary 4.5:1+(AA) 전 프리셋")
    func textOnSurfaceContrast() {
        for p in ThemePalette.all {
            let surface = rgb(p.surface)
            #expect(ratio(rgb(p.textPrimary), surface) >= 7.0, "\(p.id) textPrimary/표면")
            #expect(ratio(rgb(p.textSecondary), surface) >= 4.5, "\(p.id) textSecondary/표면")
        }
    }

    @Test("due 사다리 — today 캡슐 4.5+ · soon 캡슐(비모노)/표면(모노) 4.5+ · relaxed 캡슐 3.0+")
    func dueLadderContrast() {
        for p in ThemePalette.all {
            let surface = rgb(p.surface)
            func capsule(_ c: RGB) -> Double { ratio(c, blend(c, 0.14, over: surface)) }
            #expect(capsule(rgb(p.dueToday)) >= 4.5, "\(p.id) today/캡슐")
            let soon = rgb(p.dueSoon)
            if p.monochrome {
                #expect(ratio(soon, surface) >= 4.5, "\(p.id) soon/표면")
            } else {
                #expect(capsule(soon) >= 4.5, "\(p.id) soon/캡슐")
            }
            #expect(capsule(rgb(p.dueRelaxed)) >= 3.0, "\(p.id) relaxed/캡슐")
        }
    }
}
